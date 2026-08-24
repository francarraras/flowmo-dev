import Dispatch
import Foundation

/// Keeps evidence persistence off product actors while preserving local event
/// order. Export and deletion callers use the queue as a barrier so a pending
/// write cannot be omitted from an export or land after a completed deletion.
/// Admission is bounded: excess best-effort observations are dropped instead
/// of creating an unbounded persistence backlog.
public final class LocalEvidenceRecorder: @unchecked Sendable {
    private let queue: DispatchQueue
    private let admissionLock = NSLock()
    private var pendingRecordCount = 0
    private let recordOperation: @Sendable (FocusGuardEvidenceEvent) -> Void
    private let exportOperation: @Sendable (Date) throws -> Data

    public init(root: URL) {
        let evidence = LocalEvidence(root: root)
        self.queue = DispatchQueue(
            label: "app.flowmo.local-evidence",
            qos: .utility
        )
        self.recordOperation = { event in
            _ = evidence.record(event)
        }
        self.exportOperation = { generatedAt in
            try evidence.export(generatedAt: generatedAt)
        }
    }

    init(
        recordOperation: @escaping @Sendable (FocusGuardEvidenceEvent) -> Void,
        exportOperation: @escaping @Sendable (Date) throws -> Data
    ) {
        self.queue = DispatchQueue(
            label: "app.flowmo.local-evidence.tests",
            qos: .utility
        )
        self.recordOperation = recordOperation
        self.exportOperation = exportOperation
    }

    public func record(_ event: FocusGuardEvidenceEvent) {
        admissionLock.lock()
        guard pendingRecordCount < FlowmoEvidenceReport.maximumPendingRecords else {
            admissionLock.unlock()
            return
        }
        pendingRecordCount += 1
        admissionLock.unlock()

        let recordOperation = recordOperation
        queue.async { [self] in
            defer { finishRecord() }
            recordOperation(event)
        }
    }

    public func export(generatedAt: Date) throws -> Data {
        let exportOperation = exportOperation
        return try queue.sync {
            try exportOperation(generatedAt)
        }
    }

    /// Wait for records already submitted by this process. Call only from a
    /// product actor that has first made new Guard observations ineligible.
    public func flush() {
        queue.sync {}
    }

    private func finishRecord() {
        admissionLock.lock()
        pendingRecordCount -= 1
        admissionLock.unlock()
    }
}
