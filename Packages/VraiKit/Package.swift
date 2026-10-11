// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [
    .treatAllWarnings(as: .error)
]

let package = Package(
    name: "VraiKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "VraiGit", targets: ["VraiGit"]),
        .library(name: "VraiCore", targets: ["VraiCore"]),
        .library(name: "VraiUI", targets: ["VraiUI"])
    ],
    targets: [
        .target(name: "VraiGit", swiftSettings: strict),
        .target(name: "VraiCore", dependencies: ["VraiGit"], resources: [.process("Resources")], swiftSettings: strict),
        .target(name: "VraiUI", dependencies: ["VraiCore", "VraiGit"], swiftSettings: strict),
        .testTarget(name: "VraiGitTests", dependencies: ["VraiGit"], exclude: ["Fixtures"], swiftSettings: strict),
        .testTarget(name: "VraiCoreTests", dependencies: ["VraiCore", "VraiGit"], exclude: ["Fixtures"], resources: [.copy("Resources")], swiftSettings: strict),
        .testTarget(name: "VraiUITests", dependencies: ["VraiUI"], resources: [.copy("Resources")], swiftSettings: strict)
    ]
)
