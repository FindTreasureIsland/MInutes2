// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Minutes2",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Minutes2", targets: ["Minutes2"])],
    targets: [
        .target(name: "MinutesCore"),
        .executableTarget(name: "Minutes2", dependencies: ["MinutesCore"]),
        .testTarget(name: "MinutesCoreTests", dependencies: ["MinutesCore"])
    ]
)
