// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MorningOperator",
    defaultLocalization: "en",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "MorningCore", targets: ["MorningCore"]),
        .library(name: "MorningApple", targets: ["MorningApple"])
    ],
    targets: [
        .target(name: "MorningCore", resources: [.process("Resources")]),
        .target(name: "MorningApple", dependencies: ["MorningCore"], resources: [.process("Resources")]),
        .testTarget(name: "MorningCoreTests", dependencies: ["MorningCore"]),
        .testTarget(name: "MorningAppleTests", dependencies: ["MorningApple", "MorningCore"])
    ]
)
