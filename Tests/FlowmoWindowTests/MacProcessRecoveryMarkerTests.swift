import Darwin
import FlowmoCore
import FlowmoSync
import Foundation
import XCTest

@testable import FlowmoWindow

@MainActor
final class MacProcessRecoveryMarkerTests: XCTestCase {
    private struct LegacyMarkerFixture: Encodable {
        let pid: Int32
        let liveSessionID: UUID?
        let lastObservedAt: Date
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let currentIdentity = MacProcessRecoveryMarker.ProcessIdentity(
        pid: 200,
        startedAtSeconds: 1_799_999_000,
        startedAtMicroseconds: 123_456
    )

    func testBoundedReaderRejectsOversizedSymlinkDirectoryAndFIFO() throws {
        try withStore { store in
            let markerURL = recoveryURL(store)
            let oversized = Data(count: Int(MacProcessRecoveryMarker.maximumMarkerBytes) + 1)
            try oversized.write(to: markerURL)
            XCTAssertThrowsError(try prepareClaim(marker(for: store), world: .empty)) { error in
                guard case MacProcessRecoveryError.tooLarge = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }

            try FileManager.default.removeItem(at: markerURL)
            let target = store.root.appendingPathComponent("outside-marker.json")
            let original = Data("outside must remain unchanged".utf8)
            try original.write(to: target)
            try FileManager.default.createSymbolicLink(at: markerURL, withDestinationURL: target)
            XCTAssertThrowsError(try prepareClaim(marker(for: store), world: .empty)) { error in
                guard case MacProcessRecoveryError.unsafeTarget = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: target), original)

            try FileManager.default.removeItem(at: markerURL)
            try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: false)
            do {
                let directoryMarker = marker(for: store)
                XCTAssertThrowsError(try prepareClaim(directoryMarker, world: .empty))
                XCTAssertFalse(directoryMarker.ownsLifecycle)
            }

            try FileManager.default.removeItem(at: markerURL)
            XCTAssertEqual(mkfifo(markerURL.path, mode_t(S_IRUSR | S_IWUSR)), 0)
            XCTAssertThrowsError(try prepareClaim(marker(for: store), world: .empty)) { error in
                guard case MacProcessRecoveryError.unsafeTarget = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testAtomicClaimWritesMode0600AndCommitsOwnershipOnlyAfterExplicitCommit() throws {
        try withStore { store in
            let recovery = marker(for: store)
            var engine = Engine()
            XCTAssertEqual(try recovery.prepareClaim(&engine, now: now), .prepared)
            XCTAssertFalse(recovery.ownsLifecycle)

            var info = stat()
            XCTAssertEqual(lstat(recoveryURL(store).path, &info), 0)
            XCTAssertEqual(info.st_mode & mode_t(0o777), mode_t(0o600))

            recovery.commitPreparedClaim()
            XCTAssertTrue(recovery.ownsLifecycle)
        }
    }

    func testLifetimeClaimIsEmptyMode0600CLOEXECAndReleasesOnFinishAndDeinit() throws {
        try withStore { store in
            let recovery = marker(for: store)
            var preparation = MacProcessRecoveryMarker.ClaimPreparation.contended
            _ = try store.update { engine in
                preparation = try recovery.prepareClaim(&engine, now: self.now)
            }
            XCTAssertEqual(preparation, .prepared)
            let descriptor = try XCTUnwrap(recovery.claimedLifetimeFileDescriptor)
            XCTAssertNotEqual(fcntl(descriptor, F_GETFD) & FD_CLOEXEC, 0)

            var claimedInfo = stat()
            XCTAssertEqual(lstat(lifetimeLockURL(store).path, &claimedInfo), 0)
            XCTAssertEqual(claimedInfo.st_mode & mode_t(S_IFMT), mode_t(S_IFREG))
            XCTAssertEqual(claimedInfo.st_mode & mode_t(0o777), mode_t(0o600))
            XCTAssertEqual(claimedInfo.st_size, 0)
            recovery.commitPreparedClaim()

            _ = try store.update(
                { _ in },
                afterPersist: { _ in try recovery.finishNormally() }
            )
            XCTAssertNil(recovery.claimedLifetimeFileDescriptor)
            XCTAssertTrue(FileManager.default.fileExists(atPath: lifetimeLockURL(store).path))

            do {
                let abandoned = marker(for: store)
                _ = try store.update { engine in
                    XCTAssertEqual(try abandoned.prepareClaim(&engine, now: self.now), .prepared)
                }
                abandoned.commitPreparedClaim()
                XCTAssertNotNil(abandoned.claimedLifetimeFileDescriptor)
            }

            let afterDeinit = marker(for: store)
            _ = try store.update { engine in
                XCTAssertEqual(try afterDeinit.prepareClaim(&engine, now: self.now), .prepared)
            }
        }
    }

    func testLifetimeClaimRejectsSymlinkNonregularAndHardLinkedPaths() throws {
        try withStore { store in
            let target = store.root.appendingPathComponent("outside-lock")
            let original = Data("outside lock target".utf8)
            try original.write(to: target)
            try FileManager.default.createSymbolicLink(
                at: lifetimeLockURL(store),
                withDestinationURL: target
            )

            XCTAssertThrowsError(try prepareClaim(marker(for: store), world: .empty)) { error in
                guard case MacProcessRecoveryError.unsafeLifetimeClaim = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: target), original)
        }

        try withStore { store in
            try FileManager.default.createDirectory(
                at: lifetimeLockURL(store),
                withIntermediateDirectories: false
            )
            XCTAssertThrowsError(try prepareClaim(marker(for: store), world: .empty)) { error in
                guard case MacProcessRecoveryError.unsafeLifetimeClaim = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }

        try withStore { store in
            XCTAssertEqual(mkfifo(lifetimeLockURL(store).path, mode_t(S_IRUSR | S_IWUSR)), 0)
            XCTAssertThrowsError(try prepareClaim(marker(for: store), world: .empty)) { error in
                guard case MacProcessRecoveryError.unsafeLifetimeClaim = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }

        try withStore { store in
            let target = store.root.appendingPathComponent("hard-link-target")
            try Data().write(to: target)
            XCTAssertEqual(link(target.path, lifetimeLockURL(store).path), 0)
            XCTAssertThrowsError(try prepareClaim(marker(for: store), world: .empty)) { error in
                guard case MacProcessRecoveryError.unsafeLifetimeClaim = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        }
    }

    func testRealProcessIdentityCanClaimAndFinish() throws {
        try withStore { store in
            let recovery = MacProcessRecoveryMarker(store: store)
            var preparation = MacProcessRecoveryMarker.ClaimPreparation.contended
            _ = try store.update { engine in
                preparation = try recovery.prepareClaim(&engine, now: self.now)
            }
            XCTAssertEqual(preparation, .prepared)
            recovery.commitPreparedClaim()
            XCTAssertTrue(recovery.ownsLifecycle)

            _ = try store.update(
                { _ in },
                afterPersist: { _ in try recovery.finishNormally() }
            )
            XCTAssertFalse(recovery.ownsLifecycle)
            XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL(store).path))
        }
    }

    func testContendedControllerBlocksMutationsUntilOwnerReleasesMarker() throws {
        try withStore { store in
            let owner = MacProcessRecoveryMarker(store: store)
            var preparation = MacProcessRecoveryMarker.ClaimPreparation.contended
            _ = try store.update { engine in
                preparation = try owner.prepareClaim(&engine, now: self.now)
            }
            XCTAssertEqual(preparation, .prepared)
            owner.commitPreparedClaim()
            // The kernel-held inode, not JSON PID metadata, must be sufficient
            // to reject a genuine concurrent Mac controller.
            try FileManager.default.removeItem(at: recoveryURL(store))

            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false)
            )
            controller.beginMacProcessLifetime()
            XCTAssertTrue(controller.lifecycleNeedsRecovery)
            XCTAssertEqual(controller.activeIssue?.code, .recoveryUnavailable)

            controller.intentionDraft = "must remain blocked"
            controller.start()
            XCTAssertNil(try store.load().live)
            controller.retryLifecycleRecovery()
            XCTAssertTrue(controller.lifecycleNeedsRecovery)

            _ = try store.update(
                { _ in },
                afterPersist: { _ in try owner.finishNormally() }
            )
            controller.retryLifecycleRecovery()
            XCTAssertFalse(controller.lifecycleNeedsRecovery)

            controller.start()
            XCTAssertEqual(try store.load().live?.intention, "must remain blocked")
        }
    }

    func testNilObservationRequiresOwnershipAndClearsDurableTerminalSession() throws {
        try withStore { store in
            let unowned = marker(for: store)
            XCTAssertThrowsError(try unowned.recordObservation(nil, at: now)) { error in
                guard case MacProcessRecoveryError.ownershipLost = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }

            let world = try focusWorld(at: now)
            try store.save(world)
            let recovery = marker(for: store)
            var preparation = MacProcessRecoveryMarker.ClaimPreparation.contended
            _ = try store.update { engine in
                preparation = try recovery.prepareClaim(&engine, now: self.now)
            }
            XCTAssertEqual(preparation, .prepared)
            recovery.commitPreparedClaim()
            XCTAssertEqual(try readRecord(from: store).liveSessionID, world.live?.id)

            _ = try store.update(
                { engine in try engine.apply(.cancel, now: self.now.addingTimeInterval(1)) },
                afterPersist: { engine in
                    try recovery.recordObservation(engine.world.live?.id, at: self.now.addingTimeInterval(1))
                }
            )
            XCTAssertNil(try store.load().live)
            XCTAssertNil(try readRecord(from: store).liveSessionID)
        }
    }

    func testControllerCloseClearsPriorSessionIDAfterWorldIsDurable() throws {
        try withStore { store in
            try store.save(.empty)
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false)
            )
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "terminal marker"
            controller.start()
            controller.skip()
            let sessionID = try XCTUnwrap(controller.world.live?.id)
            XCTAssertEqual(try readRecord(from: store).liveSessionID, sessionID)

            controller.stopFocus()
            controller.skip()
            controller.skip()
            controller.dismissCloseBeat()

            XCTAssertNil(try store.load().live)
            XCTAssertNil(try readRecord(from: store).liveSessionID)
        }
    }

    func testForgedVersionedAndLegacyLiveProcessMetadataCannotContend() throws {
        try withStore { store in
            let world = try focusWorld(at: now)
            let sessionID = try XCTUnwrap(world.live?.id)
            try store.save(world)
            let unrelatedLiveIdentity = MacProcessRecoveryMarker.ProcessIdentity(
                pid: 100,
                startedAtSeconds: 1_799_998_000,
                startedAtMicroseconds: 10
            )
            try writeRecord(
                identity: unrelatedLiveIdentity,
                sessionID: sessionID,
                observedAt: now,
                to: store
            )

            let versionedRecovery = marker(for: store) { pid in
                XCTAssertNotEqual(pid, unrelatedLiveIdentity.pid, "foreign PID metadata must not be authoritative")
                return self.currentIdentity
            }
            var versionedPreparation = MacProcessRecoveryMarker.ClaimPreparation.contended
            let versioned = try store.update { engine in
                versionedPreparation = try versionedRecovery.prepareClaim(
                    &engine,
                    now: self.now.addingTimeInterval(5)
                )
            }
            XCTAssertEqual(versionedPreparation, .prepared)
            versionedRecovery.commitPreparedClaim()
            XCTAssertTrue(try XCTUnwrap(versioned.world.live).isPaused)
            _ = try store.update(
                { _ in },
                afterPersist: { _ in try versionedRecovery.finishNormally() }
            )
        }

        try withStore { store in
            let world = try focusWorld(at: now)
            let sessionID = try XCTUnwrap(world.live?.id)
            try store.save(world)
            try writeLegacyRecord(
                pid: 100,
                sessionID: sessionID,
                observedAt: now,
                to: store
            )
            let legacyRecovery = marker(for: store) { pid in
                XCTAssertNotEqual(pid, 100, "legacy foreign PID metadata must not be authoritative")
                return self.currentIdentity
            }
            var legacyPreparation = MacProcessRecoveryMarker.ClaimPreparation.contended
            let legacy = try store.update { engine in
                legacyPreparation = try legacyRecovery.prepareClaim(
                    &engine,
                    now: self.now.addingTimeInterval(5)
                )
            }
            XCTAssertEqual(legacyPreparation, .prepared)
            legacyRecovery.commitPreparedClaim()
            XCTAssertTrue(try XCTUnwrap(legacy.world.live).isPaused)
        }
    }

    func testDeadMarkerPausesOnlyMatchingSessionAndClampsFutureObservation() throws {
        try withStore { store in
            let world = try focusWorld(at: now)
            let sessionID = try XCTUnwrap(world.live?.id)
            let deadIdentity = MacProcessRecoveryMarker.ProcessIdentity(
                pid: 100,
                startedAtSeconds: 1_799_998_000,
                startedAtMicroseconds: 0
            )
            let recoveryNow = now.addingTimeInterval(20)
            try writeRecord(
                identity: deadIdentity,
                sessionID: sessionID,
                observedAt: recoveryNow.addingTimeInterval(3_600),
                to: store
            )
            do {
                let matchingMarker = marker(for: store) { pid in
                    pid == deadIdentity.pid ? nil : self.currentIdentity
                }
                var matchingEngine = Engine(world: world)
                XCTAssertEqual(try matchingMarker.prepareClaim(&matchingEngine, now: recoveryNow), .prepared)
                XCTAssertEqual(try XCTUnwrap(matchingEngine.world.live).pausedAt, recoveryNow)
            }

            try writeRecord(
                identity: deadIdentity,
                sessionID: UUID(),
                observedAt: recoveryNow,
                to: store
            )
            let cliMarker = marker(for: store) { pid in
                pid == deadIdentity.pid ? nil : self.currentIdentity
            }
            var cliEngine = Engine(world: world)
            XCTAssertEqual(try cliMarker.prepareClaim(&cliEngine, now: recoveryNow), .prepared)
            XCTAssertFalse(try XCTUnwrap(cliEngine.world.live).isPaused)
        }
    }

    func testWorldSaveFailureAfterPreparedClaimRemainsRetryable() throws {
        try withStore { store in
            let world = try focusWorld(at: now)
            try store.save(world)
            let originalWorldData = try Data(contentsOf: store.worldURL)
            let sessionID = try XCTUnwrap(world.live?.id)
            let deadIdentity = MacProcessRecoveryMarker.ProcessIdentity(
                pid: 100,
                startedAtSeconds: 1_799_998_000,
                startedAtMicroseconds: 0
            )
            try writeRecord(identity: deadIdentity, sessionID: sessionID, observedAt: now, to: store)
            let recovery = marker(for: store) { pid in
                pid == deadIdentity.pid ? nil : self.currentIdentity
            }

            XCTAssertThrowsError(
                try store.update { engine in
                    XCTAssertEqual(
                        try recovery.prepareClaim(&engine, now: self.now.addingTimeInterval(10)),
                        .prepared
                    )
                    try FileManager.default.removeItem(at: store.worldURL)
                    try FileManager.default.createDirectory(at: store.worldURL, withIntermediateDirectories: false)
                }
            )
            XCTAssertFalse(recovery.ownsLifecycle)

            try FileManager.default.removeItem(at: store.worldURL)
            try originalWorldData.write(to: store.worldURL)
            var preparation = MacProcessRecoveryMarker.ClaimPreparation.contended
            let retried = try store.update { engine in
                preparation = try recovery.prepareClaim(&engine, now: self.now.addingTimeInterval(11))
            }
            XCTAssertEqual(preparation, .prepared)
            recovery.commitPreparedClaim()
            XCTAssertTrue(recovery.ownsLifecycle)
            XCTAssertTrue(try XCTUnwrap(retried.world.live).isPaused)
        }
    }

    func testImmediateCLIContinueThenCrashPreservesFrozenClocksAcrossPhases() throws {
        for phase in [SessionPhase.prime, .focus, .onBreak, .recall, .closeBeat] {
            try withStore { store in
                let fixture = try pausedWorld(in: phase, origin: now)
                let pausedLive = try XCTUnwrap(fixture.world.live)
                try store.save(fixture.world)

                let deadIdentity = MacProcessRecoveryMarker.ProcessIdentity(
                    pid: 100,
                    startedAtSeconds: 1_799_998_000,
                    startedAtMicroseconds: 0
                )
                try writeRecord(
                    identity: deadIdentity,
                    sessionID: pausedLive.id,
                    observedAt: fixture.pausedAt.addingTimeInterval(-5),
                    to: store
                )

                let continuedAt = fixture.pausedAt.addingTimeInterval(100)
                let continued = try store.update { engine in
                    try engine.apply(.continue, now: continuedAt)
                }
                XCTAssertEqual(continued.world.live?.id, pausedLive.id)
                XCTAssertFalse(try XCTUnwrap(continued.world.live).isPaused)
                XCTAssertEqual(continued.world.live?.lastResumedAt, continuedAt)
                XCTAssertEqual(try store.load().live?.lastResumedAt, continuedAt)

                let recovery = marker(for: store)
                var preparation = MacProcessRecoveryMarker.ClaimPreparation.contended
                let recovered = try store.update { engine in
                    preparation = try recovery.prepareClaim(
                        &engine,
                        now: continuedAt.addingTimeInterval(10)
                    )
                }

                XCTAssertEqual(preparation, .prepared, "phase: \(phase)")
                let recoveredLive = try XCTUnwrap(recovered.world.live)
                XCTAssertEqual(recoveredLive.id, pausedLive.id, "phase: \(phase)")
                XCTAssertEqual(recoveredLive.phase, phase)
                XCTAssertEqual(recoveredLive.pausedAt, continuedAt, "phase: \(phase)")
                XCTAssertEqual(recoveredLive.frozenElapsed, pausedLive.frozenElapsed, "phase: \(phase)")
                XCTAssertEqual(recoveredLive.frozenRemaining, pausedLive.frozenRemaining, "phase: \(phase)")
            }
        }
    }

    func testFutureResumeBoundaryIsClampedToRecoveryNow() throws {
        try withStore { store in
            let fixture = try pausedWorld(in: .focus, origin: now)
            let continuedAt = fixture.pausedAt.addingTimeInterval(100)
            var continued = try store.update { engine in
                engine.world = fixture.world
                try engine.apply(.continue, now: continuedAt)
            }.world
            continued.live?.lastResumedAt = continuedAt.addingTimeInterval(3_600)
            try store.save(continued)
            try writeRecord(
                identity: MacProcessRecoveryMarker.ProcessIdentity(
                    pid: 100,
                    startedAtSeconds: 1_799_998_000,
                    startedAtMicroseconds: 0
                ),
                sessionID: continued.live?.id,
                observedAt: fixture.pausedAt,
                to: store
            )

            let recoveryNow = continuedAt.addingTimeInterval(10)
            let recovery = marker(for: store)
            let recovered = try store.update { engine in
                XCTAssertEqual(
                    try recovery.prepareClaim(&engine, now: recoveryNow),
                    .prepared
                )
            }
            XCTAssertEqual(try XCTUnwrap(recovered.world.live).pausedAt, recoveryNow)
        }
    }

    func testMacContinuePersistsBoundaryAndRestartUsesReplacementSession() throws {
        try withStore { store in
            try store.save(try pausedFocusWorld(at: Date().addingTimeInterval(-200)))
            let originalID = try XCTUnwrap(store.load().live?.id)
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false)
            )
            controller.beginMacProcessLifetime()

            controller.continueSession()

            let continued = try XCTUnwrap(store.load().live)
            let resumedAt = try XCTUnwrap(continued.lastResumedAt)
            XCTAssertEqual(continued.id, originalID)
            XCTAssertFalse(continued.isPaused)
            XCTAssertEqual(try readRecord(from: store).liveSessionID, originalID)
            XCTAssertEqual(
                try readRecord(from: store).lastObservedAt.timeIntervalSinceReferenceDate,
                resumedAt.timeIntervalSinceReferenceDate,
                accuracy: 0.001
            )

            XCTAssertTrue(controller.pauseForRecovery())
            controller.restartSession()

            let replacement = try XCTUnwrap(store.load().live)
            XCTAssertNotEqual(replacement.id, originalID)
            XCTAssertNil(replacement.lastResumedAt)
            XCTAssertEqual(try readRecord(from: store).liveSessionID, replacement.id)
        }
    }

    func testAfterPersistHoldsWorldLockAndAllowsLegitimateCLITakeoverAfterRelease() throws {
        try withStore { store in
            try store.save(try pausedFocusWorld(at: now))
            let attempted = DispatchSemaphore(value: 0)
            let completed = DispatchSemaphore(value: 0)
            let takeoverDate = now.addingTimeInterval(30)

            _ = try store.update(
                { _ in },
                afterPersist: { _ in
                    DispatchQueue.global().async {
                        attempted.signal()
                        _ = try? store.update { engine in
                            try engine.apply(.continue, now: takeoverDate)
                        }
                        completed.signal()
                    }
                    XCTAssertEqual(attempted.wait(timeout: .now() + 1), .success)
                    XCTAssertEqual(completed.wait(timeout: .now() + 0.1), .timedOut)
                }
            )
            XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
            XCTAssertFalse(try XCTUnwrap(store.load().live).isPaused)
        }
    }

    func testMarkerRemovalFailureLeavesDurablyPausedWorldAndMarker() throws {
        try withStore { store in
            let world = try focusWorld(at: now)
            try store.save(world)
            let recovery = marker(for: store)
            var preparation = MacProcessRecoveryMarker.ClaimPreparation.contended
            _ = try store.update { engine in
                preparation = try recovery.prepareClaim(&engine, now: self.now)
            }
            XCTAssertEqual(preparation, .prepared)
            recovery.commitPreparedClaim()

            let markerURL = recoveryURL(store)
            try FileManager.default.removeItem(at: markerURL)
            try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: false)

            XCTAssertThrowsError(
                try store.update(
                    { engine in
                        try engine.apply(.pauseForRecovery, now: self.now.addingTimeInterval(10))
                    },
                    afterPersist: { _ in try recovery.finishNormally() }
                )
            )
            XCTAssertTrue(try XCTUnwrap(store.load().live).isPaused)
            var info = stat()
            XCTAssertEqual(lstat(markerURL.path, &info), 0)
            XCTAssertEqual(info.st_mode & mode_t(S_IFMT), mode_t(S_IFDIR))
        }
    }

    func testFailedSleepPauseRetriesSameSession() throws {
        try withStore { store in
            try store.save(try focusWorld(at: now))
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            try makeDirectoryReadOnly(store.root)
            defer { _ = chmod(store.root.path, mode_t(0o700)) }

            XCTAssertFalse(controller.pauseForRecovery())
            XCTAssertTrue(controller.lifecycleNeedsRecovery)
            XCTAssertFalse(try XCTUnwrap(store.load().live).isPaused)

            XCTAssertEqual(chmod(store.root.path, mode_t(0o700)), 0)
            controller.retryLifecycleRecovery()
            XCTAssertTrue(try XCTUnwrap(store.load().live).isPaused)
            XCTAssertFalse(controller.lifecycleNeedsRecovery)
        }
    }

    func testFailedSleepPauseDoesNotPauseReplacementCLISession() throws {
        try withStore { store in
            try store.save(try focusWorld(at: now))
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            try makeDirectoryReadOnly(store.root)
            defer { _ = chmod(store.root.path, mode_t(0o700)) }
            XCTAssertFalse(controller.pauseForRecovery())

            XCTAssertEqual(chmod(store.root.path, mode_t(0o700)), 0)
            let replacement = try store.update { engine in
                try engine.apply(.cancel, now: self.now.addingTimeInterval(5))
                try engine.apply(.start(intention: "CLI takeover"), now: self.now.addingTimeInterval(6))
                try engine.apply(.skip, now: self.now.addingTimeInterval(6))
            }
            let replacementID = try XCTUnwrap(replacement.world.live?.id)

            controller.retryLifecycleRecovery()
            let loaded = try store.load()
            XCTAssertEqual(loaded.live?.id, replacementID)
            XCTAssertFalse(try XCTUnwrap(loaded.live).isPaused)
            XCTAssertFalse(controller.lifecycleNeedsRecovery)
        }
    }

    func testLifecycleMarkerFailureBlocksSessionUIWithoutMisclassifyingWorld() throws {
        try withStore { store in
            try store.save(try focusWorld(at: now))
            let target = store.root.appendingPathComponent("marker-target")
            try Data("not a marker".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: recoveryURL(store), withDestinationURL: target)

            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            controller.setDisplayMode(.mini)
            controller.beginMacProcessLifetime()

            XCTAssertTrue(controller.lifecycleNeedsRecovery)
            XCTAssertFalse(controller.storeNeedsRecovery)
            XCTAssertEqual(controller.effectiveWindowContentSize, DisplayMode.classic.windowContentSize)
            XCTAssertEqual(controller.activeIssue?.code, .recoveryUnavailable)
        }
    }

    func testRemoteLiveSessionIsNotPausedOrClaimedByMacRecovery() throws {
        try withStore { store in
            let startedAt = Date().addingTimeInterval(-120)
            let remoteWorld = try focusWorld(at: startedAt)
            let sessionID = try XCTUnwrap(remoteWorld.live?.id)
            try store.save(remoteWorld)
            try WorldSyncMetadataStore(root: store.root).save(
                WorldSyncMetadata(remoteLiveSessionID: sessionID)
            )
            try writeRecord(
                identity: .init(
                    pid: 321,
                    startedAtSeconds: UInt64(startedAt.timeIntervalSince1970),
                    startedAtMicroseconds: 0
                ),
                sessionID: sessionID,
                observedAt: startedAt.addingTimeInterval(30),
                to: store
            )

            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false)
            )
            controller.beginMacProcessLifetime()

            let loaded = try store.load()
            XCTAssertEqual(loaded.live?.id, sessionID)
            XCTAssertFalse(try XCTUnwrap(loaded.live).isPaused)
            XCTAssertNil(try readRecord(from: store).liveSessionID)
            XCTAssertFalse(controller.lifecycleNeedsRecovery)
        }
    }

    func testPostLaunchLifecycleFailureExpandsMiniWindowForRecoveryPane() throws {
        try withStore { store in
            try store.save(.empty)
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false)
            )
            controller.beginMacProcessLifetime()
            controller.setDisplayMode(.mini)

            let delegate = AppDelegate(controller: controller)
            let window = delegate.makeWindow()
            delegate.window = window
            delegate.observeWindowContentSize()

            XCTAssertEqual(window.contentView?.frame.size, DisplayMode.mini.windowContentSize)

            try FileManager.default.removeItem(at: recoveryURL(store))
            try FileManager.default.createDirectory(
                at: recoveryURL(store),
                withIntermediateDirectories: false
            )
            controller.intentionDraft = "must remain blocked"
            controller.start()

            XCTAssertTrue(controller.lifecycleNeedsRecovery)
            XCTAssertEqual(controller.displayMode, .mini)
            XCTAssertEqual(controller.effectiveWindowContentSize, DisplayMode.classic.windowContentSize)
            XCTAssertEqual(window.contentView?.frame.size, DisplayMode.classic.windowContentSize)
            XCTAssertEqual(window.contentMinSize, DisplayMode.classic.windowContentSize)
            XCTAssertEqual(window.contentMaxSize, DisplayMode.classic.windowContentSize)
            XCTAssertNil(try store.load().live)

            try FileManager.default.removeItem(at: recoveryURL(store))
            controller.retryLifecycleRecovery()

            XCTAssertFalse(controller.lifecycleNeedsRecovery)
            XCTAssertEqual(controller.displayMode, .mini)
            XCTAssertEqual(window.contentView?.frame.size, DisplayMode.mini.windowContentSize)
            XCTAssertEqual(window.contentMinSize, DisplayMode.mini.windowContentSize)
            XCTAssertEqual(window.contentMaxSize, DisplayMode.mini.windowContentSize)
        }
    }

    func testMacDeleteAllClearsPlantedSessionIDAndExactOrphanTempsOnly() throws {
        try withStore { store in
            var world = World.empty
            world.profile.lastIntention = "private canonical data"
            try store.save(world)
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false)
            )
            controller.beginMacProcessLifetime()
            XCTAssertEqual(
                LocalEvidence(root: store.root).record(.promptOfferedAfterConfirmedHide),
                .recorded
            )

            let plantedID = UUID()
            try plantSessionID(plantedID, in: store)
            let exact = store.root.appendingPathComponent(
                ".mac-process-recovery.write-\(UUID().uuidString).tmp"
            )
            let badUUID = store.root.appendingPathComponent(".mac-process-recovery.write-not-a-uuid.tmp")
            let extraSuffix = store.root.appendingPathComponent(
                ".mac-process-recovery.write-\(UUID().uuidString).tmp.keep"
            )
            try Data(plantedID.uuidString.utf8).write(to: exact)
            try Data("keep bad UUID".utf8).write(to: badUUID)
            try Data("keep extra suffix".utf8).write(to: extraSuffix)
            var lockBefore = stat()
            XCTAssertEqual(lstat(lifetimeLockURL(store).path, &lockBefore), 0)

            controller.deleteAllData()

            XCTAssertEqual(controller.userNotice, "All Flowmo data was deleted.")
            XCTAssertFalse(controller.lifecycleNeedsRecovery)
            XCTAssertNil(try readRecord(from: store).liveSessionID)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: store.root.appendingPathComponent("evidence.json").path
                )
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: exact.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: badUUID.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: extraSuffix.path))
            var lockAfter = stat()
            XCTAssertEqual(lstat(lifetimeLockURL(store).path, &lockAfter), 0)
            XCTAssertEqual(lockAfter.st_dev, lockBefore.st_dev)
            XCTAssertEqual(lockAfter.st_ino, lockBefore.st_ino)
            XCTAssertEqual(lockAfter.st_size, 0)
            XCTAssertFalse(
                String(decoding: try Data(contentsOf: recoveryURL(store)), as: UTF8.self)
                    .contains(plantedID.uuidString)
            )
        }
    }

    func testMacDeleteAllWithoutCloudTransportPreservesContentFreeDeletionIntent() throws {
        try withStore { store in
            var privateWorld = World.empty
            privateWorld.profile.lastIntention = "private cloud deletion proof"
            try store.save(privateWorld)
            let snapshot = WorldSyncSnapshot(world: privateWorld, generation: UUID())
            try WorldSyncMetadataStore(root: store.root).save(
                WorldSyncMetadata(
                    accountRecordName: "opaque-old-account",
                    base: snapshot
                )
            )
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false)
            )
            controller.beginMacProcessLifetime()

            controller.deleteAllData()

            let metadataStore = WorldSyncMetadataStore(root: store.root)
            let metadata = try metadataStore.load()
            XCTAssertTrue(metadata.cloudDeletionPending)
            XCTAssertEqual(metadata.cloudDeletionAccountRecordName, "opaque-old-account")
            XCTAssertTrue(try XCTUnwrap(metadata.pending).isEffectivelyEmpty)
            XCTAssertNil(metadata.base)
            XCTAssertEqual(controller.activeIssue?.code, .dataDeletionIncomplete)
            let encoded = String(decoding: try Data(contentsOf: metadataStore.stateURL), as: UTF8.self)
            XCTAssertFalse(encoded.contains("private cloud deletion proof"))
        }
    }

    func testMacDeleteAllNeverRecursivelyRemovesExactNamedTempDirectory() throws {
        try withStore { store in
            try store.save(.empty)
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false)
            )
            controller.beginMacProcessLifetime()
            let plantedID = UUID()
            try plantSessionID(plantedID, in: store)

            let directory = store.root.appendingPathComponent(
                ".mac-process-recovery.write-\(UUID().uuidString).tmp"
            )
            let child = directory.appendingPathComponent("keep.txt")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("must survive".utf8).write(to: child)

            controller.deleteAllData()

            XCTAssertFalse(controller.lifecycleNeedsRecovery)
            XCTAssertNil(controller.userNotice)
            XCTAssertEqual(controller.activeIssue?.code, .dataDeletionIncomplete)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
            XCTAssertEqual(try Data(contentsOf: child), Data("must survive".utf8))
            XCTAssertNil(try readRecord(from: store).liveSessionID)
        }
    }

    func testMacDeleteAllReportsCombinedStoreAndMarkerCleanupAsIncomplete() throws {
        try withStore { store in
            try store.save(.empty)
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false)
            )
            controller.beginMacProcessLifetime()

            let storeDirectory = store.root.appendingPathComponent(
                ".world.write-\(UUID().uuidString).tmp"
            )
            let storeChild = storeDirectory.appendingPathComponent("keep-store.txt")
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: false)
            try Data("store recovery data remains".utf8).write(to: storeChild)

            let markerDirectory = store.root.appendingPathComponent(
                ".mac-process-recovery.write-\(UUID().uuidString).tmp"
            )
            let markerChild = markerDirectory.appendingPathComponent("keep-marker.txt")
            try FileManager.default.createDirectory(at: markerDirectory, withIntermediateDirectories: false)
            try Data("marker recovery data remains".utf8).write(to: markerChild)

            controller.deleteAllData()

            XCTAssertFalse(controller.lifecycleNeedsRecovery)
            XCTAssertNil(controller.userNotice)
            XCTAssertEqual(controller.activeIssue?.code, .dataDeletionIncomplete)
            XCTAssertEqual(try store.load(), .empty)
            XCTAssertNil(try readRecord(from: store).liveSessionID)
            XCTAssertEqual(try Data(contentsOf: storeChild), Data("store recovery data remains".utf8))
            XCTAssertEqual(try Data(contentsOf: markerChild), Data("marker recovery data remains".utf8))

            controller.retryLifecycleRecovery()
            XCTAssertEqual(controller.activeIssue?.code, .dataDeletionIncomplete)
        }
    }

    func testLifecycleRetryRestoresPendingDeletionWarningAfterMarkerSafetyFailure() throws {
        try withStore { store in
            try store.save(.empty)
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false)
            )
            controller.beginMacProcessLifetime()

            let storeDirectory = store.root.appendingPathComponent(
                ".world.write-\(UUID().uuidString).tmp"
            )
            let storeChild = storeDirectory.appendingPathComponent("keep.txt")
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: false)
            try Data("recovery data remains".utf8).write(to: storeChild)

            try FileManager.default.removeItem(at: recoveryURL(store))
            try FileManager.default.createDirectory(
                at: recoveryURL(store),
                withIntermediateDirectories: false
            )

            controller.deleteAllData()

            XCTAssertTrue(controller.lifecycleNeedsRecovery)
            XCTAssertNil(controller.userNotice)
            XCTAssertEqual(controller.activeIssue?.code, .recoveryUnavailable)
            XCTAssertEqual(try Data(contentsOf: storeChild), Data("recovery data remains".utf8))

            try FileManager.default.removeItem(at: recoveryURL(store))
            controller.retryLifecycleRecovery()

            XCTAssertFalse(controller.lifecycleNeedsRecovery)
            XCTAssertEqual(controller.activeIssue?.code, .dataDeletionIncomplete)
            XCTAssertEqual(try Data(contentsOf: storeChild), Data("recovery data remains".utf8))
            XCTAssertNil(try readRecord(from: store).liveSessionID)
        }
    }

    func testConstructingAndClaimingNeverResumesPausedSession() throws {
        try withStore { store in
            let paused = try pausedFocusWorld(at: now)
            try store.save(paused)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            controller.beginMacProcessLifetime()
            XCTAssertTrue(controller.world.live?.isPaused == true)
            XCTAssertTrue(try XCTUnwrap(store.load().live).isPaused)
        }
    }

    private func marker(
        for store: Store,
        lookup: @escaping (Int32) throws -> MacProcessRecoveryMarker.ProcessIdentity? = { _ in nil }
    ) -> MacProcessRecoveryMarker {
        MacProcessRecoveryMarker(
            store: store,
            ownerID: UUID(),
            processID: currentIdentity.pid,
            processIdentity: currentIdentity,
            identityLookup: { pid in
                if pid == self.currentIdentity.pid { return self.currentIdentity }
                return try lookup(pid)
            }
        )
    }

    private func prepareClaim(_ recovery: MacProcessRecoveryMarker, world: World) throws {
        var engine = Engine(world: world)
        _ = try recovery.prepareClaim(&engine, now: now)
    }

    private func writeRecord(
        identity: MacProcessRecoveryMarker.ProcessIdentity,
        sessionID: UUID?,
        observedAt: Date,
        to store: Store
    ) throws {
        let record = MacProcessRecoveryMarker.Record(
            version: MacProcessRecoveryMarker.Record.currentVersion,
            ownerID: UUID(),
            pid: identity.pid,
            processStartedAtSeconds: identity.startedAtSeconds,
            processStartedAtMicroseconds: identity.startedAtMicroseconds,
            liveSessionID: sessionID,
            lastObservedAt: observedAt
        )
        try JSONEncoder().encode(record).write(to: recoveryURL(store))
    }

    private func writeLegacyRecord(
        pid: Int32,
        sessionID: UUID?,
        observedAt: Date,
        to store: Store
    ) throws {
        try JSONEncoder().encode(
            LegacyMarkerFixture(
                pid: pid,
                liveSessionID: sessionID,
                lastObservedAt: observedAt
            )
        ).write(to: recoveryURL(store))
    }

    private func readRecord(from store: Store) throws -> MacProcessRecoveryMarker.Record {
        try JSONDecoder().decode(
            MacProcessRecoveryMarker.Record.self,
            from: Data(contentsOf: recoveryURL(store))
        )
    }

    private func plantSessionID(_ sessionID: UUID, in store: Store) throws {
        let record = try readRecord(from: store)
        try JSONEncoder().encode(
            MacProcessRecoveryMarker.Record(
                version: record.version,
                ownerID: record.ownerID,
                pid: record.pid,
                processStartedAtSeconds: record.processStartedAtSeconds,
                processStartedAtMicroseconds: record.processStartedAtMicroseconds,
                liveSessionID: sessionID,
                lastObservedAt: record.lastObservedAt
            )
        ).write(to: recoveryURL(store))
    }

    private func focusWorld(at date: Date) throws -> World {
        var engine = Engine()
        try engine.apply(.start(intention: "recovery proof"), now: date)
        try engine.apply(.skip, now: date)
        return engine.world
    }

    private func pausedFocusWorld(at date: Date) throws -> World {
        var engine = Engine(world: try focusWorld(at: date))
        try engine.apply(.pauseForRecovery, now: date.addingTimeInterval(10))
        return engine.world
    }

    private func pausedWorld(in phase: SessionPhase, origin: Date) throws -> (world: World, pausedAt: Date) {
        var engine = Engine()
        try engine.apply(.start(intention: "resume boundary proof"), now: origin)
        let pausedAt: Date
        switch phase {
        case .prime:
            pausedAt = origin.addingTimeInterval(30)
        case .focus:
            try engine.apply(.skip, now: origin)
            pausedAt = origin.addingTimeInterval(95)
        case .onBreak:
            try engine.apply(.skip, now: origin)
            try engine.apply(.stopFocus, now: origin.addingTimeInterval(100))
            pausedAt = origin.addingTimeInterval(105)
        case .recall:
            try engine.apply(.skip, now: origin)
            try engine.apply(.stopFocus, now: origin.addingTimeInterval(100))
            try engine.apply(.skip, now: origin.addingTimeInterval(105))
            pausedAt = origin.addingTimeInterval(110)
        case .closeBeat:
            try engine.apply(.skip, now: origin)
            try engine.apply(.stopFocus, now: origin.addingTimeInterval(100))
            try engine.apply(.skip, now: origin.addingTimeInterval(105))
            try engine.apply(.skip, now: origin.addingTimeInterval(110))
            pausedAt = origin.addingTimeInterval(115)
        }
        try engine.apply(.pauseForRecovery, now: pausedAt)
        return (engine.world, pausedAt)
    }

    private func recoveryURL(_ store: Store) -> URL {
        store.root.appendingPathComponent("mac-process-recovery.json")
    }

    private func lifetimeLockURL(_ store: Store) -> URL {
        store.root.appendingPathComponent("mac-process-recovery.lock")
    }

    private func makeDirectoryReadOnly(_ url: URL) throws {
        guard chmod(url.path, mode_t(0o500)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-window-recovery-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            _ = chmod(root.path, mode_t(0o700))
            try? FileManager.default.removeItem(at: root)
        }
        try body(Store(root: root))
    }
}
