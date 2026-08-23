// swift-tools-version: 6.0
import PackageDescription

let infoPlist = Context.packageDirectory + "/Sources/FlowmoApp/Info.plist"

let package = Package(
    name: "flowmo",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "FlowmoCore", targets: ["FlowmoCore"]),
        .library(name: "FlowmoLook", targets: ["FlowmoLook"]),
        .library(name: "FlowmoWindow", targets: ["FlowmoWindow"]),
        .library(name: "FlowmoPhone", targets: ["FlowmoPhone"]),
        .executable(name: "flowmo", targets: ["FlowmoApp"]),
    ],
    targets: [
        .target(name: "FlowmoCore"),
        .target(name: "FlowmoLook", dependencies: ["FlowmoCore"]),
        .target(name: "FlowmoWindow", dependencies: ["FlowmoCore", "FlowmoLook"]),
        .target(name: "FlowmoPhone", dependencies: ["FlowmoCore", "FlowmoLook"]),
        .target(name: "FlowmoCLI", dependencies: ["FlowmoCore"]),
        .target(name: "FlowmoCheck", dependencies: ["FlowmoCore"]),
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
        .testTarget(name: "FlowmoCLITests", dependencies: ["FlowmoCLI", "FlowmoCore"]),
        .testTarget(name: "FlowmoWindowTests", dependencies: ["FlowmoWindow", "FlowmoCore"]),
    ]
)
