// swift-tools-version: 6.0
import PackageDescription

let infoPlist = Context.packageDirectory + "/Sources/FlowmoApp/Info.plist"

let package = Package(
    name: "flowmo",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "FlowmoCore", targets: ["FlowmoCore"]),
        .library(name: "FlowmoWindow", targets: ["FlowmoWindow"]),
        .executable(name: "flowmo", targets: ["FlowmoApp"]),
    ],
    targets: [
        .target(name: "FlowmoCore"),
        .target(name: "FlowmoWindow", dependencies: ["FlowmoCore"]),
        .target(name: "FlowmoCLI", dependencies: ["FlowmoCore"]),
        .target(name: "FlowmoCheck", dependencies: ["FlowmoCore"]),
        .executableTarget(
            name: "FlowmoApp",
            dependencies: ["FlowmoWindow", "FlowmoCLI", "FlowmoCheck"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ], .when(platforms: [.macOS])),
            ]
        ),
    ]
)
