// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "flowmo",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "FlowmoCore", targets: ["FlowmoCore"]),
        .executable(name: "flowmo", targets: ["FlowmoCLI"]),
        .executable(name: "flowmo-check", targets: ["FlowmoCheck"]),
    ],
    targets: [
        .target(name: "FlowmoCore"),
        .executableTarget(name: "FlowmoCLI", dependencies: ["FlowmoCore"]),
        .executableTarget(name: "FlowmoCheck", dependencies: ["FlowmoCore"]),
    ]
)
