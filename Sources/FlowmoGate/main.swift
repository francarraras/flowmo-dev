import Darwin
import FlowmoCore
import Foundation

private let maximumReportBytes = 256 * 1024

private enum GateToolError: LocalizedError {
    case usage
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return nil
        case .invalidInput(let message):
            return message
        }
    }
}

@main
private enum FlowmoGateTool {
    static func main() {
        do {
            let code = try run(Array(CommandLine.arguments.dropFirst()))
            exit(code)
        } catch GateToolError.usage {
            printUsage(to: .standardError)
            exit(64)
        } catch {
            let message =
                (error as? LocalizedError)?.errorDescription
                ?? "The gate could not be evaluated."
            write("error: \(message)", to: .standardError)
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws -> Int32 {
        if arguments == ["-h"] || arguments == ["--help"] {
            printUsage(to: .standardOutput)
            return 0
        }
        guard arguments.count == 5,
            let supervisedAttempts = Int(arguments[2]),
            let firstEligibleAt = parseISO8601(arguments[3]),
            ["clean", "incident"].contains(arguments[4])
        else {
            throw GateToolError.usage
        }

        let start = try decodeReport(at: arguments[0])
        let end = try decodeReport(at: arguments[1])
        let result = FocusGuardResumptionGate.evaluate(
            start: start,
            end: end,
            supervisedEligibleAttempts: supervisedAttempts,
            firstEligibleAttemptAt: firstEligibleAt,
            integrityIncident: arguments[4] == "incident"
        )

        print("WP3 gate: \(result.decision.rawValue.uppercased())")
        print("Supervised eligible attempts: \(result.supervisedEligibleAttempts)")
        print("Recorded eligible attempts: \(result.recordedEligibleAttempts)")
        print("Confirmed attempts: \(result.confirmedAttempts)")
        print("Recorded failures: \(result.recordedFailures)")
        if let upperBound = result.oneSidedFailureUpperBound {
            print(String(format: "One-sided 95%% failure upper bound: %.4f", upperBound))
        }
        if !result.reasons.isEmpty {
            print("Reasons: \(result.reasons.map(\.rawValue).joined(separator: ", "))")
        }

        switch result.decision {
        case .pass: return 0
        case .inconclusive: return 2
        case .fail, .invalid: return 1
        }
    }

    private static func decodeReport(at path: String) throws -> FlowmoEvidenceReport {
        let data = try boundedRegularFile(at: path)
        do {
            return try JSONDecoder.flowmo.decode(FlowmoEvidenceReport.self, from: data)
        } catch {
            throw GateToolError.invalidInput("A supplied file is not a supported evidence export.")
        }
    }

    private static func boundedRegularFile(at path: String) throws -> Data {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw GateToolError.invalidInput("A supplied evidence export could not be opened safely.")
        }
        defer { close(descriptor) }

        var information = stat()
        guard fstat(descriptor, &information) == 0,
            (information.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            information.st_size >= 0,
            information.st_size <= maximumReportBytes
        else {
            throw GateToolError.invalidInput("A supplied evidence export is not a bounded regular file.")
        }

        var data = Data()
        data.reserveCapacity(Int(information.st_size))
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let remaining = maximumReportBytes + 1 - data.count
            guard remaining > 0 else {
                throw GateToolError.invalidInput("A supplied evidence export is too large.")
            }
            let amount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, min(bytes.count, remaining))
            }
            if amount == 0 { break }
            if amount < 0 {
                if errno == EINTR { continue }
                throw GateToolError.invalidInput("A supplied evidence export could not be read safely.")
            }
            data.append(contentsOf: buffer.prefix(amount))
        }
        guard data.count <= maximumReportBytes else {
            throw GateToolError.invalidInput("A supplied evidence export is too large.")
        }
        return data
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: value) { return parsed }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func printUsage(to handle: FileHandle) {
        write(
            """
            Usage: swift run flowmo-wp3-gate START.json END.json ELIGIBLE_ATTEMPTS FIRST_ELIGIBLE_AT clean|incident

            FIRST_ELIGIBLE_AT must be ISO 8601. Use `incident` if the supervised
            run had a recorder, store, export, crash, or other integrity problem.
            Exit status: 0 pass, 1 fail/invalid, 2 inconclusive, 64 usage error.
            """,
            to: handle
        )
    }

    private static func write(_ text: String, to handle: FileHandle) {
        handle.write(Data((text + "\n").utf8))
    }
}
