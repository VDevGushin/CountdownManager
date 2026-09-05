// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CountdownManager",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CountdownManager", targets: ["CountdownManager"])],
    targets: [
        .target(name: "CountdownCore"),
        .target(
            name: "CountdownManagerUI",
            dependencies: ["CountdownCore"],
            path: "Sources/CountdownManager"
        ),
        .executableTarget(
            name: "CountdownManager",
            dependencies: ["CountdownManagerUI"],
            path: "Sources/CountdownManagerApp"
        ),
        .executableTarget(name: "CoreChecks", dependencies: ["CountdownCore"], path: "Tests/CountdownCoreTests"),
        .executableTarget(
            name: "UIChecks",
            dependencies: ["CountdownCore", "CountdownManagerUI"],
            path: "Tests/CountdownManagerUITests"
        )
    ]
)
