// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CountdownManager",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CountdownManager", targets: ["CountdownManager"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "CountdownCore"),
        .target(
            name: "CountdownManagerUI",
            dependencies: ["CountdownCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/CountdownManager",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
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
