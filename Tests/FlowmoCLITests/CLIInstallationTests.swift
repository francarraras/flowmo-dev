import CryptoKit
import Darwin
import Foundation
import XCTest

final class CLIInstallationTests: XCTestCase {
    func testInstalledNativeExecutableFindsAdjacentBundleAfterSourceRemoval() throws {
        try withFixture { root in
            let source = try makeSource(root, name: "native source", value: "artwork proof")
            let swift = root.appendingPathComponent("probe.swift")
            try """
            import Foundation
            let url = Bundle.main.bundleURL.appendingPathComponent("flowmo_FlowmoLook.bundle")
            guard let bundle = Bundle(url: url),
                  let file = bundle.url(forResource: "HorizonStudy", withExtension: "png"),
                  let value = try? String(contentsOf: file, encoding: .utf8)
            else { fatalError("adjacent resource unavailable") }
            print(value)
            print(CommandLine.arguments.dropFirst().joined(separator: "|"))
            """.write(to: swift, atomically: true, encoding: .utf8)
            let build = try run(
                "/usr/bin/xcrun",
                [
                    "swiftc", "-module-cache-path", root.appendingPathComponent("module-cache").path,
                    swift.path, "-o", source.appendingPathComponent("flowmo").path,
                ], root: root)
            XCTAssertEqual(build.code, 0, build.output)
            let prefix = root.appendingPathComponent("installed with spaces ' $literal")
            let installed = try install(
                ["--binary", source.appendingPathComponent("flowmo").path, "--prefix", prefix.path], root: root)
            XCTAssertEqual(installed.code, 0, installed.output)
            try FileManager.default.removeItem(at: source)
            let arguments = ["two words", "$HOME", "'quoted'", "--json", "line\nbreak"]
            let result = try run(prefix.appendingPathComponent("bin/flowmo").path, arguments, root: root)
            XCTAssertEqual(result.code, 0, result.output)
            XCTAssertEqual(result.output, "artwork proof\n" + arguments.joined(separator: "|") + "\n")
        }
    }

    func testExplicitUpgradeSwitchesCompletePayloadAndPreservesOldPayloadAndStore() throws {
        try withFixture { root in
            let source = try makeSource(root, name: "first", value: "first")
            let next = try makeSource(root, name: "second", value: "second")
            let prefix = root.appendingPathComponent("installed")
            let store = root.appendingPathComponent("session/world.json")
            try FileManager.default.createDirectory(
                at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
            let privateBytes = Data("synthetic unchanged session".utf8)
            try privateBytes.write(to: store)
            XCTAssertEqual(
                try install(
                    ["--binary", source.appendingPathComponent("flowmo").path, "--prefix", prefix.path], root: root
                ).code, 0)
            let entry = prefix.appendingPathComponent("bin/flowmo")
            let before = try Data(contentsOf: entry)
            let oldPayload = try XCTUnwrap(payloads(prefix).first)
            let rejected = try install(
                ["--binary", next.appendingPathComponent("flowmo").path, "--prefix", prefix.path], root: root)
            XCTAssertNotEqual(rejected.code, 0)
            XCTAssertEqual(try Data(contentsOf: entry), before)
            let upgraded = try install(
                ["--binary", next.appendingPathComponent("flowmo").path, "--prefix", prefix.path, "--replace"],
                root: root)
            XCTAssertEqual(upgraded.code, 0, upgraded.output)
            let after = try Data(contentsOf: entry)
            XCTAssertNotEqual(before, after)
            XCTAssertTrue(FileManager.default.fileExists(atPath: oldPayload.appendingPathComponent("flowmo").path))
            let newPayload = try XCTUnwrap(payloads(prefix).first { $0 != oldPayload })
            let resources = newPayload.appendingPathComponent(
                "flowmo_FlowmoLook.bundle/HorizonStudy.png")
            XCTAssertEqual(try String(contentsOf: resources, encoding: .utf8), "second")
            XCTAssertEqual(try run(entry.path, [], root: root).output, "second\n")
            XCTAssertEqual(try Data(contentsOf: store), privateBytes)
        }
    }

    func testUpgradeAcceptsLegacyRegularBinaryButRejectsForeignLauncher() throws {
        try withFixture { root in
            let source = try makeSource(root, name: "source", value: "new")
            let prefix = root.appendingPathComponent("installed")
            let bin = prefix.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let entry = bin.appendingPathComponent("flowmo")
            try Data("legacy executable".utf8).write(to: entry)
            let upgrade = try install(
                ["--binary", source.appendingPathComponent("flowmo").path, "--prefix", prefix.path, "--upgrade"],
                root: root)
            XCTAssertEqual(upgrade.code, 0, upgrade.output)
            XCTAssertTrue(try String(contentsOf: entry, encoding: .utf8).contains("# Flowmo CLI launcher v1"))
            XCTAssertEqual(try run(entry.path, [], root: root).output, "new\n")
            try FileManager.default.removeItem(at: entry)
            let foreign = root.appendingPathComponent("unrelated")
            try Data("untouched".utf8).write(to: foreign)
            try FileManager.default.createSymbolicLink(atPath: entry.path, withDestinationPath: foreign.path)
            let rejected = try install(
                ["--binary", source.appendingPathComponent("flowmo").path, "--prefix", prefix.path, "--replace"],
                root: root)
            XCTAssertNotEqual(rejected.code, 0)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: entry.path), foreign.path)
            XCTAssertEqual(try String(contentsOf: foreign, encoding: .utf8), "untouched")
        }
    }

    func testPackagedInstallVerifiesResourcesAndRejectsIncompleteOrAlteredPayloadBeforeWriting() throws {
        for mutation in [
            "valid", "missing-bundle", "missing-art", "changed", "extra", "symlink-file", "symlink-bundle",
            "manifest-traversal",
        ] {
            try withFixture { root in
                let source = try makeSource(root, name: "package", value: "packaged")
                let bundle = source.appendingPathComponent("flowmo_FlowmoLook.bundle")
                let art = bundle.appendingPathComponent("HorizonStudy.png")
                let installer = source.appendingPathComponent("install.sh")
                try FileManager.default.copyItem(at: script, to: installer)
                try writeChecksums(source)
                switch mutation {
                case "missing-bundle": try FileManager.default.removeItem(at: bundle)
                case "missing-art": try FileManager.default.removeItem(at: art)
                case "changed": try Data("changed".utf8).write(to: art)
                case "extra": try Data("extra".utf8).write(to: bundle.appendingPathComponent("extra.png"))
                case "symlink-file":
                    try FileManager.default.removeItem(at: art)
                    try FileManager.default.createSymbolicLink(
                        atPath: art.path, withDestinationPath: source.appendingPathComponent("flowmo").path)
                case "symlink-bundle":
                    let moved = root.appendingPathComponent("other-bundle")
                    try FileManager.default.moveItem(at: bundle, to: moved)
                    try FileManager.default.createSymbolicLink(atPath: bundle.path, withDestinationPath: moved.path)
                case "manifest-traversal":
                    try Data((String(repeating: "0", count: 64) + "  ../unrelated\n").utf8).write(
                        to: source.appendingPathComponent("SHA256SUMS"))
                default: break
                }
                let prefix = root.appendingPathComponent("installed")
                let result = try run("/bin/bash", [installer.path, "--prefix", prefix.path], root: root)
                if mutation == "valid" {
                    XCTAssertEqual(result.code, 0, result.output)
                    XCTAssertEqual(
                        try run(prefix.appendingPathComponent("bin/flowmo").path, [], root: root).output, "packaged\n")
                } else {
                    XCTAssertNotEqual(result.code, 0, mutation)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: prefix.path), mutation)
                }
            }
        }
    }

    func testMissingLocalResourceCannotReplaceWorkingInstallation() throws {
        try withFixture { root in
            let source = try makeSource(root, name: "source", value: "old")
            let prefix = root.appendingPathComponent("installed")
            XCTAssertEqual(
                try install(
                    ["--binary", source.appendingPathComponent("flowmo").path, "--prefix", prefix.path], root: root
                ).code, 0)
            let entry = prefix.appendingPathComponent("bin/flowmo")
            let before = try Data(contentsOf: entry)
            try FileManager.default.removeItem(at: source.appendingPathComponent("flowmo_FlowmoLook.bundle"))
            XCTAssertNotEqual(
                try install(
                    ["--binary", source.appendingPathComponent("flowmo").path, "--prefix", prefix.path, "--replace"],
                    root: root
                ).code, 0)
            XCTAssertEqual(try Data(contentsOf: entry), before)
            XCTAssertEqual(try run(entry.path, [], root: root).output, "old\n")
        }
    }

    func testInterruptAfterLauncherPublicationKeepsCompleteInstalledPayload() throws {
        for upgrade in [false, true] {
            try withFixture { root in
                let source = try makeSource(root, name: "source", value: "complete")
                let prefix = root.appendingPathComponent("installed")
                var arguments = ["--binary", source.appendingPathComponent("flowmo").path, "--prefix", prefix.path]
                if upgrade {
                    XCTAssertEqual(try install(arguments, root: root).code, 0)
                    arguments.append("--replace")
                }
                let wrappers = root.appendingPathComponent("wrappers")
                try FileManager.default.createDirectory(at: wrappers, withIntermediateDirectories: true)
                let ruby = """
                    #!/bin/bash
                    if [ "$1" = '-e' ] && [ "$2" = 'File.rename(ARGV[0], ARGV[1])' ]; then
                      /usr/bin/ruby "$@" || exit "$?"
                      kill -TERM "$PPID"
                      exit 0
                    fi
                    exec /usr/bin/ruby "$@"
                    """
                let link = """
                    #!/bin/bash
                    /bin/ln "$@" || exit "$?"
                    kill -TERM "$PPID"
                    """
                for (name, contents) in [("ruby", ruby), ("ln", link)] {
                    let file = wrappers.appendingPathComponent(name)
                    try contents.write(to: file, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
                }
                let result = try run(
                    "/bin/bash", [script.path] + arguments, root: root,
                    environment: ["PATH": wrappers.path + ":/usr/bin:/bin:/usr/sbin:/sbin"])
                XCTAssertEqual(result.code, 143, result.output)
                try FileManager.default.removeItem(at: source)
                XCTAssertEqual(
                    try run(prefix.appendingPathComponent("bin/flowmo").path, [], root: root).output, "complete\n")
                let installedPayloads = try payloads(prefix)
                XCTAssertEqual(installedPayloads.count, upgrade ? 2 : 1)
                for payload in installedPayloads {
                    XCTAssertEqual(
                        try String(
                            contentsOf: payload.appendingPathComponent("flowmo_FlowmoLook.bundle/HorizonStudy.png"),
                            encoding: .utf8),
                        "complete")
                }
            }
        }
    }

    func testOptionShapedPathsDoNotCreateDirectoriesAndExplicitRelativePathWorks() throws {
        try withFixture { root in
            for option in ["--help", "--replace", "--unknown"] {
                XCTAssertNotEqual(try install(["--prefix", option], root: root).code, 0)
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(option).path))
            }
            let source = try makeSource(root, name: "source", value: "relative")
            let result = try install(
                ["--binary", source.appendingPathComponent("flowmo").path, "--prefix", "./--name"], root: root)
            XCTAssertEqual(result.code, 0, result.output)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("--name/bin/flowmo").path))
        }
    }

    func testCopyPreservesExtendedAttributesOnExecutableAndArtwork() throws {
        try withFixture { root in
            let source = try makeSource(root, name: "source", value: "attributes")
            let prefix = root.appendingPathComponent("installed")
            for relative in ["flowmo", "flowmo_FlowmoLook.bundle/HorizonStudy.png"] {
                XCTAssertEqual(
                    try run(
                        "/usr/bin/xattr",
                        ["-w", "com.flowmo.install-proof", "synthetic", source.appendingPathComponent(relative).path],
                        root: root
                    ).code, 0)
            }
            XCTAssertEqual(
                try install(
                    ["--binary", source.appendingPathComponent("flowmo").path, "--prefix", prefix.path], root: root
                ).code, 0)
            let payload = try XCTUnwrap(payloads(prefix).first)
            for relative in ["flowmo", "flowmo_FlowmoLook.bundle/HorizonStudy.png"] {
                let result = try run(
                    "/usr/bin/xattr",
                    ["-p", "com.flowmo.install-proof", payload.appendingPathComponent(relative).path], root: root)
                XCTAssertEqual(result.code, 0, result.output)
                XCTAssertEqual(result.output, "synthetic\n")
            }
        }
    }

    private var script: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Scripts/install-cli")
    }

    private func payloads(_ prefix: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: prefix.appendingPathComponent("libexec/flowmo"), includingPropertiesForKeys: nil
        ).filter { !$0.lastPathComponent.hasPrefix(".") }
    }

    private func makeSource(_ root: URL, name: String, value: String) throws -> URL {
        let source = root.appendingPathComponent(name)
        let bundle = source.appendingPathComponent("flowmo_FlowmoLook.bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let binary = source.appendingPathComponent("flowmo")
        try "#!/bin/sh\nprintf '%s\\n' '\(value)'\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        try Data(value.utf8).write(to: bundle.appendingPathComponent("HorizonStudy.png"))
        return source
    }

    private func writeChecksums(_ source: URL) throws {
        let rows = try ["flowmo", "flowmo_FlowmoLook.bundle/HorizonStudy.png"].map { relative in
            let data = try Data(contentsOf: source.appendingPathComponent(relative))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return "\(digest)  \(relative)\n"
        }
        try rows.joined().write(to: source.appendingPathComponent("SHA256SUMS"), atomically: true, encoding: .utf8)
    }

    private func install(_ args: [String], root: URL) throws -> (code: Int32, output: String) {
        try run("/bin/bash", [script.path] + args, root: root)
    }

    private func run(
        _ executable: String, _ args: [String], root: URL, environment: [String: String] = [:]
    ) throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = root
        process.environment = ProcessInfo.processInfo.environment.merging([
            "FLOWMO_HOME": root.appendingPathComponent("session").path
        ]) { _, value in value }.merging(environment) { _, value in value }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning, Date() < deadline { usleep(10_000) }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            throw NSError(domain: "CLIInstallationTests.timeout", code: 1)
        }
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func withFixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "flowmo-install-proof-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
