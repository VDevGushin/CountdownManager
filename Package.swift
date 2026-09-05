// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CountdownManager",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CountdownManager", targets: ["CountdownManager"])],
    targets: [
        .target(name: "CountdownCore"),
        .executableTarget(name: "CountdownManager", dependencies: ["CountdownCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["CountdownCore"], path: "Tests/CountdownCoreTests")
    ]
)
