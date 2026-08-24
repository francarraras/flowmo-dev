import Foundation
import XCTest

@testable import FlowmoCore

final class PersistenceAndFormatSecurityTests: XCTestCase {
    func testOversizedWorldIsRejectedBeforeDecode() throws {
        try withStore { store in
            try Data(count: Int(WorldPersistenceLimits.maximumFileBytes) + 1).write(to: store.worldURL)

            XCTAssertThrowsError(try store.load()) { error in
                guard case StoreError.worldTooLarge(let actual, let maximum) = error else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertGreaterThan(actual, maximum)
            }
        }
    }

    func testValidLegacyWorldStillMigrates() throws {
        try withStore { store in
            let legacy = Data(
                #"""
                {
                  "live": {
                    "id": "11111111-1111-1111-1111-111111111111",
                    "label": "legacy focus",
                    "state": "paused",
                    "breakRatio": 5,
                    "startedAt": "2024-01-01T00:00:00.000Z",
                    "phaseStartedAt": "2024-01-01T00:01:00.000Z",
                    "encodingStartedAt": "2024-01-01T00:01:00.000Z",
                    "primeDuration": 120,
                    "recallDuration": 300,
                    "pausedElapsed": 10
                  },
                  "profile": { "breakRatio": 5 },
                  "config": { "primeSeconds": 120, "recallSeconds": 300, "defaultBreakRatio": 5 },
                  "history": []
                }
                """#.utf8)
            try legacy.write(to: store.worldURL)

            let world = try store.load()
            XCTAssertEqual(world.live?.phase, .focus)
            XCTAssertEqual(world.live?.intention, "legacy focus")
            XCTAssertEqual(world.live?.frozenElapsed, 10)
            XCTAssertNil(world.live?.lastResumedAt)
            XCTAssertEqual(world.live?.recallDuration, 180)
            XCTAssertEqual(world.config.recallSeconds, 180)
        }
    }

    func testContinueBoundaryRoundTripsAndInvalidBoundaryIsRejected() throws {
        try withStore { store in
            let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
            let resumedAt = startedAt.addingTimeInterval(200)
            var engine = Engine()
            try engine.apply(.start(intention: "resume boundary"), now: startedAt)
            try engine.apply(.skip, now: startedAt)
            try engine.apply(.pauseForRecovery, now: startedAt.addingTimeInterval(100))
            try engine.apply(.continue, now: resumedAt)

            try store.save(engine.world)
            XCTAssertEqual(try store.load().live?.lastResumedAt, resumedAt)

            var invalid = engine.world
            invalid.live?.lastResumedAt = Date(
                timeIntervalSince1970: WorldPersistenceLimits.maximumDateSecondsSince1970 + 1
            )
            try writeUnvalidated(invalid, to: store)
            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertTrue(error.localizedDescription.contains("$.live.lastResumedAt"))
            }
        }
    }

    func testExtremeFiniteDurationIsRejected() throws {
        try withStore { store in
            var world = World.empty
            world.config.primeSeconds = 1e300
            try writeUnvalidated(world, to: store)

            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertTrue(error.localizedDescription.contains("$.config.primeSeconds"))
            }
        }
    }

    func testIntMaxCounterIsRejectedAndLearnerDoesNotTrap() throws {
        var profile = Profile.default
        profile.sessionCount = .max
        let learned = ProfileLearner.apply(profile, focusSeconds: .greatestFiniteMagnitude)
        XCTAssertEqual(learned.sessionCount, WorldPersistenceLimits.maximumCounter)
        XCTAssertEqual(learned.totalFocusSeconds, WorldPersistenceLimits.maximumAggregateSeconds)
        XCTAssertLessThanOrEqual(learned.recentFocusSeconds.count, 5)

        try withStore { store in
            var world = World.empty
            world.profile.sessionCount = .max
            try writeUnvalidated(world, to: store)
            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertTrue(error.localizedDescription.contains("$.profile.sessionCount"))
            }
        }
    }

    func testLearnerKeepsValidBoundaryProfilePersistable() throws {
        var profile = Profile.default
        profile.sessionCount = WorldPersistenceLimits.maximumCounter
        profile.totalFocusSeconds = WorldPersistenceLimits.maximumAggregateSeconds

        let learned = ProfileLearner.apply(profile, focusSeconds: 1)

        XCTAssertEqual(learned.sessionCount, WorldPersistenceLimits.maximumCounter)
        XCTAssertEqual(learned.totalFocusSeconds, WorldPersistenceLimits.maximumAggregateSeconds)
        var world = World.empty
        world.profile = learned
        XCTAssertNoThrow(try world.validateForPersistence())
    }

    func testOversizedCollectionAndTextAreRejected() throws {
        try withStore { store in
            var world = World.empty
            world.profile.recentFocusSeconds = Array(
                repeating: 1,
                count: WorldPersistenceLimits.maximumRecentFocusCount + 1
            )
            try writeUnvalidated(world, to: store)
            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertTrue(error.localizedDescription.contains("$.profile.recentFocusSeconds"))
            }

            world = .empty
            world.profile.lastIntention = String(
                repeating: "x",
                count: WorldPersistenceLimits.maximumIntentionBytes + 1
            )
            try writeUnvalidated(world, to: store)
            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertTrue(error.localizedDescription.contains("$.profile.lastIntention"))
            }
        }
    }

    func testRawOversizedGuardListCannotHideBehindNormalization() throws {
        try withStore { store in
            let encoded = try JSONEncoder.flowmo.encode(World.empty)
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            var config = try XCTUnwrap(root["config"] as? [String: Any])
            var guardConfig = try XCTUnwrap(config["focusGuard"] as? [String: Any])
            guardConfig["bundleIdentifiers"] = Array(
                repeating: "com.example.same",
                count: WorldPersistenceLimits.maximumGuardIdentifierCount + 1
            )
            config["focusGuard"] = guardConfig
            root["config"] = config
            try JSONSerialization.data(withJSONObject: root).write(to: store.worldURL)

            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertTrue(error.localizedDescription.contains("raw array"))
            }
        }
    }

    func testSymlinkWorldIsRejected() throws {
        try withStore { store in
            let target = store.root.appendingPathComponent("outside.json")
            try JSONEncoder.flowmo.encode(World.empty).write(to: target)
            try FileManager.default.createSymbolicLink(at: store.worldURL, withDestinationURL: target)

            XCTAssertThrowsError(try store.load()) { error in
                guard case StoreError.unsafeWorldTarget = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testQuarantineSurvivesResetButDeleteAllDataRemovesIt() throws {
        try withStore { store in
            let invalid = Data("{ definitely invalid".utf8)
            try invalid.write(to: store.worldURL)

            let result = try store.quarantineInvalidWorldAndReset()

            XCTAssertEqual(result.originalURL, store.worldURL)
            XCTAssertEqual(try Data(contentsOf: result.quarantineURL), invalid)
            XCTAssertEqual(try store.load(), .empty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.quarantineURL.path))
            XCTAssertFalse(result.invalidReason.isEmpty)

            let reset = try store.resetToEmpty()
            XCTAssertTrue(
                reset.preservedQuarantineURLs.map(\.lastPathComponent).contains(result.quarantineURL.lastPathComponent)
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.quarantineURL.path))

            let similarlyNamedNonStoreFile = store.root.appendingPathComponent("world.invalid-not-owned.json")
            try Data("not a Store quarantine".utf8).write(to: similarlyNamedNonStoreFile)
            let deletion = try store.deleteAllData()
            XCTAssertEqual(deletion.removedQuarantineCount, 1)
            XCTAssertEqual(
                deletion.removedQuarantineURLs.first?.lastPathComponent, result.quarantineURL.lastPathComponent)
            XCTAssertFalse(FileManager.default.fileExists(atPath: result.quarantineURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: similarlyNamedNonStoreFile.path))
            XCTAssertEqual(try store.load(), .empty)
        }
    }

    func testDeleteAllDataNeverRecursivelyDeletesDirectoryArtifact() throws {
        try withStore { store in
            var world = World.empty
            world.profile.lastIntention = "private canonical text"
            try store.save(world)

            let directory = store.root.appendingPathComponent("world.invalid-\(UUID().uuidString).json")
            let child = directory.appendingPathComponent("keep.txt")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("child must survive".utf8).write(to: child)

            XCTAssertThrowsError(try store.deleteAllData()) { error in
                guard let deletionError = error as? StoreDataDeletionError else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertTrue(deletionError.remainingRecoveryArtifactsKnown)
                XCTAssertEqual(deletionError.removedRecoveryArtifactCount, 0)
                XCTAssertEqual(deletionError.remainingRecoveryArtifactCount, 1)
                XCTAssertEqual(
                    deletionError.remainingRecoveryArtifactURLs.first?.lastPathComponent,
                    directory.lastPathComponent
                )
            }

            XCTAssertEqual(try store.load(), .empty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
            XCTAssertEqual(try Data(contentsOf: child), Data("child must survive".utf8))
        }
    }

    func testDeleteAllDataRemovesExactCrashTempButKeepsSimilarNames() throws {
        try withStore { store in
            var world = World.empty
            world.profile.lastIntention = "private canonical text"
            try store.save(world)

            let plantedSecret = "PLANTED-ORPHAN-PRIVATE-TEXT"
            let exact = store.root.appendingPathComponent(".world.write-\(UUID().uuidString).tmp")
            let badUUID = store.root.appendingPathComponent(".world.write-not-a-uuid.tmp")
            let extraSuffix = store.root.appendingPathComponent(".world.write-\(UUID().uuidString).tmp.keep")
            try Data(plantedSecret.utf8).write(to: exact)
            try Data("keep bad UUID".utf8).write(to: badUUID)
            try Data("keep extra suffix".utf8).write(to: extraSuffix)
            XCTAssertTrue(String(decoding: try Data(contentsOf: exact), as: UTF8.self).contains(plantedSecret))

            let deletion = try store.deleteAllData()

            XCTAssertEqual(deletion.removedRecoveryArtifactCount, 1)
            XCTAssertEqual(deletion.removedQuarantineCount, 0)
            XCTAssertEqual(deletion.removedRecoveryArtifactURLs.first?.lastPathComponent, exact.lastPathComponent)
            XCTAssertFalse(FileManager.default.fileExists(atPath: exact.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: badUUID.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: extraSuffix.path))
            XCTAssertEqual(try store.load(), .empty)
            XCTAssertFalse(
                String(decoding: try Data(contentsOf: store.worldURL), as: UTF8.self).contains(plantedSecret))
        }
    }

    func testDeleteAllDataRemovesLocalEvidenceAndItsExactCrashTemp() throws {
        try withStore { store in
            var world = World.empty
            world.profile.lastIntention = "private canonical text"
            try store.save(world)

            let evidence = LocalEvidence(root: store.root)
            XCTAssertEqual(evidence.record(.promptOfferedAfterConfirmedHide), .recorded)
            let exactTemporary = store.root.appendingPathComponent(
                ".evidence.write-\(UUID().uuidString).tmp"
            )
            let similarlyNamed = store.root.appendingPathComponent(".evidence.write-not-a-uuid.tmp")
            try Data("private aggregate state".utf8).write(to: exactTemporary)
            try Data("not owned".utf8).write(to: similarlyNamed)

            let deletion = try store.deleteAllData()

            XCTAssertEqual(deletion.removedEvidenceArtifactCount, 2)
            XCTAssertEqual(
                Set(deletion.removedEvidenceArtifactURLs.map(\.lastPathComponent)),
                Set(["evidence.json", exactTemporary.lastPathComponent])
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: exactTemporary.path))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: store.root.appendingPathComponent("evidence.json").path
                )
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: similarlyNamed.path))
            XCTAssertEqual(try store.load(), .empty)

            let report = try JSONDecoder.flowmo.decode(
                FlowmoEvidenceReport.self,
                from: evidence.export(generatedAt: Date(timeIntervalSince1970: 1))
            )
            XCTAssertEqual(report.counters.map(\.count), Array(repeating: 0, count: EvidenceSignal.allCases.count))
        }
    }

    func testDeleteAllDataReportsEvidenceArtifactWithoutRecursing() throws {
        try withStore { store in
            var world = World.empty
            world.profile.lastIntention = "private canonical text"
            try store.save(world)

            let evidence = LocalEvidence(root: store.root)
            XCTAssertEqual(evidence.record(.promptOfferedAfterConfirmedHide), .recorded)
            let directory = store.root.appendingPathComponent(
                ".evidence.write-\(UUID().uuidString).tmp"
            )
            let child = directory.appendingPathComponent("keep.txt")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("child must survive".utf8).write(to: child)

            XCTAssertThrowsError(try store.deleteAllData()) { error in
                guard let deletionError = error as? StoreDataDeletionError else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertTrue(deletionError.remainingEvidenceArtifactsKnown)
                XCTAssertEqual(deletionError.removedEvidenceArtifactCount, 1)
                XCTAssertEqual(deletionError.remainingEvidenceArtifactCount, 1)
                XCTAssertEqual(
                    deletionError.remainingEvidenceArtifactURLs.first?.lastPathComponent,
                    directory.lastPathComponent
                )
            }

            XCTAssertEqual(try store.load(), .empty)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: store.root.appendingPathComponent("evidence.json").path
                )
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
            XCTAssertEqual(try Data(contentsOf: child), Data("child must survive".utf8))
        }
    }

    func testMigrationPreservesCorruptDestinationBeforeReplacement() throws {
        let fm = FileManager.default
        let oldRoot = fm.temporaryDirectory
            .appendingPathComponent("flowmo-migration-source-\(UUID().uuidString)", isDirectory: true)
        let newRoot = fm.temporaryDirectory
            .appendingPathComponent("flowmo-migration-destination-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fm.removeItem(at: oldRoot)
            try? fm.removeItem(at: newRoot)
        }

        var sourceWorld = World.empty
        sourceWorld.profile.lastIntention = "preserved migration"
        try Store(root: oldRoot).save(sourceWorld)
        try fm.createDirectory(at: newRoot, withIntermediateDirectories: true)
        let invalid = Data("corrupt destination".utf8)
        let destination = Store(root: newRoot)
        try invalid.write(to: destination.worldURL)

        XCTAssertTrue(try Store.migrateWorld(from: oldRoot, to: newRoot))
        XCTAssertEqual(try destination.load(), sourceWorld)

        let quarantine = try XCTUnwrap(
            fm.contentsOfDirectory(at: newRoot, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("world.invalid-") }
        )
        XCTAssertEqual(try Data(contentsOf: quarantine), invalid)
    }

    func testExportReturnsValidatedCurrentJSON() throws {
        try withStore { store in
            var world = World.empty
            world.profile.lastIntention = "export me"
            try store.save(world)

            let exported = try store.exportCurrentWorldJSON()
            let decoded = try JSONDecoder.flowmo.decode(World.self, from: exported)
            XCTAssertEqual(decoded, world)
        }
    }

    func testResetAndDeleteRefuseLiveSessionAndResetSucceedsWhenIdle() throws {
        try withStore { store in
            var engine = Engine()
            try engine.apply(.start(intention: "still live"), now: Date())
            try store.save(engine.world)

            XCTAssertThrowsError(try store.resetToEmpty()) { error in
                XCTAssertEqual(error as? StoreError, .liveSessionPreventsReset)
            }
            XCTAssertThrowsError(try store.deleteAllData()) { error in
                XCTAssertEqual(error as? StoreError, .liveSessionPreventsReset)
            }
            XCTAssertNotNil(try store.load().live)

            engine.world.live = nil
            engine.world.profile.lastIntention = "delete me"
            try store.save(engine.world)
            let result = try store.resetToEmpty()
            XCTAssertEqual(try store.load(), .empty)
            XCTAssertEqual(result.worldURL, store.worldURL)
        }
    }

    func testFormattingIsTotalForNonfiniteAndHugeValues() {
        XCTAssertEqual(Format.clock(.nan), Format.corruptionIndicator)
        XCTAssertEqual(Format.clock(.infinity), Format.corruptionIndicator)
        XCTAssertEqual(Format.clock(1e300), Format.corruptionIndicator)
        XCTAssertEqual(Format.remainingClock(1e300), Format.corruptionIndicator)
        XCTAssertEqual(Format.minutes(.nan), Format.corruptionIndicator)
        XCTAssertEqual(Format.remainingSeconds(.nan), 0)
        XCTAssertEqual(Format.remainingSeconds(.infinity), .max)
        XCTAssertEqual(Format.remainingSeconds(1e300), .max)
        XCTAssertEqual(Format.clock(65), "01:05")
        XCTAssertEqual(Format.remainingClock(0.2), "00:01")
    }

    func testLiveViewSanitizesUserTerminalControlsWithoutChangingLayout() {
        let hostile = "café 🚀\n\u{1B}]0;owned\u{7}\u{9B}31m\u{7F}\u{2028}\u{2029}done"
        var status = SessionStatus(
            phase: nil,
            isPaused: false,
            intention: "",
            lastIntention: hostile,
            elapsed: 65,
            remaining: nil,
            phaseDuration: nil,
            focusSeconds: 65,
            breakSeconds: 13,
            earnedBreakSeconds: 13,
            captures: [],
            recallText: "",
            todayFocusSeconds: 65,
            ratio: 5
        )

        let idle = Format.liveView(status)
        assertTerminalFrame(idle, lineCount: 4)
        XCTAssertTrue(idle.contains("café 🚀"))

        status.phase = .focus
        status.intention = hostile
        let focus = Format.liveView(status)
        assertTerminalFrame(focus, lineCount: 3)
        XCTAssertTrue(focus.contains("café 🚀"))

        status.phase = .closeBeat
        status.recallText = hostile
        status.captures = [CaptureItem(text: hostile, createdAt: Date())]
        let close = Format.liveView(status)
        assertTerminalFrame(close, lineCount: 5)
        XCTAssertEqual(close.components(separatedBy: "\n").filter { $0.contains("café 🚀") }.count, 2)
    }

    func testAggregateHelpersSaturateInsteadOfOverflowing() {
        let date = Date()
        let sessions = (0..<2).map { index in
            CompletedSession(
                id: UUID(),
                intention: "\(index)",
                focusSeconds: .greatestFiniteMagnitude,
                breakSeconds: 0,
                captureCount: 0,
                recallText: nil,
                endedAt: date
            )
        }
        let world = World(live: nil, profile: .default, config: .default, history: sessions)
        XCTAssertEqual(world.todayFocusSeconds(now: date), .greatestFiniteMagnitude)
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-persistence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(root: root))
    }

    private func writeUnvalidated(_ world: World, to store: Store) throws {
        try JSONEncoder.flowmo.encode(world).write(to: store.worldURL, options: .atomic)
    }

    private func assertTerminalFrame(
        _ frame: String,
        lineCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lines = frame.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, lineCount, file: file, line: line)
        for renderedLine in lines {
            XCTAssertFalse(
                renderedLine.unicodeScalars.contains { scalar in
                    let code = scalar.value
                    return code <= 0x1F
                        || code == 0x7F
                        || (0x80...0x9F).contains(code)
                        || code == 0x2028
                        || code == 0x2029
                },
                "terminal control survived in rendered user line",
                file: file,
                line: line
            )
        }
    }
}
