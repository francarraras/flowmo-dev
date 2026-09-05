// swift-tools-version: 6.0
import PackageDescription

let infoPlist = Context.packageDirectory + "/Sources/FlowmoApp/Info.plist"

let package = Package(
    name: "flowmo",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "FlowmoCore", targets: ["FlowmoCore"]),
        .library(name: "FlowmoActivity", targets: ["FlowmoActivity"]),
        .library(name: "FlowmoSync", targets: ["FlowmoSync"]),
        .library(name: "FlowmoLook", targets: ["FlowmoLook"]),
        .library(name: "FlowmoWindow", targets: ["FlowmoWindow"]),
        .library(name: "FlowmoPhone", targets: ["FlowmoPhone"]),
        .executable(name: "flowmo", targets: ["FlowmoApp"]),
        .executable(name: "flowmo-wp3-gate", targets: ["FlowmoGate"]),
    ],
    targets: [
        .target(name: "FlowmoCore"),
        .target(name: "FlowmoActivity", dependencies: ["FlowmoCore"]),
        .target(name: "FlowmoSync", dependencies: ["FlowmoCore"]),
        .target(name: "FlowmoLook", dependencies: ["FlowmoCore"], resources: [.process("Resources")]),
        .target(name: "FlowmoWindow", dependencies: ["FlowmoCore", "FlowmoLook", "FlowmoSync"]),
        .target(name: "FlowmoPhone", dependencies: ["FlowmoCore", "FlowmoActivity", "FlowmoLook", "FlowmoSync"]),
        .target(name: "FlowmoCLI", dependencies: ["FlowmoCore"]),
        .target(name: "FlowmoCheck", dependencies: ["FlowmoCore"]),
        .executableTarget(name: "FlowmoGate", dependencies: ["FlowmoCore"]),
        .executableTarget(
            name: "FlowmoApp",
            dependencies: ["FlowmoWindow", "FlowmoCLI", "FlowmoCheck"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-Xlinker", "-sectcreate",
                        "-Xlinker", "__TEXT",
                        "-Xlinker", "__info_plist",
                        "-Xlinker", infoPlist,
                    ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(name: "FlowmoCoreTests", dependencies: ["FlowmoCore"]),
        .testTarget(name: "FlowmoActivityTests", dependencies: ["FlowmoActivity", "FlowmoCore"]),
        .testTarget(name: "FlowmoSyncTests", dependencies: ["FlowmoSync", "FlowmoCore"]),
        .testTarget(name: "FlowmoCLITests", dependencies: ["FlowmoCLI", "FlowmoCore"]),
        .testTarget(name: "FlowmoWindowTests", dependencies: ["FlowmoWindow", "FlowmoCore", "FlowmoSync"]),
        .testTarget(
            name: "FlowmoPhoneTests", dependencies: ["FlowmoPhone", "FlowmoCore", "FlowmoActivity", "FlowmoSync"]),
    ]
)
