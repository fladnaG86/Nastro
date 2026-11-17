// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nastro",
    platforms: [.macOS("15.0")],
    targets: [
        .target(name: "NastroCore", path: "Sources/NastroCore"),
        .target(name: "NastroMedia", dependencies: ["NastroCore"], path: "Sources/NastroMedia"),
        .executableTarget(name: "Nastro", dependencies: ["NastroCore", "NastroMedia"], path: "Sources/Nastro"),
        .executableTarget(name: "NastroProbe", dependencies: ["NastroMedia"], path: "Sources/NastroProbe"),
        .testTarget(name: "NastroCoreTests", dependencies: ["NastroCore"], path: "Tests/NastroCoreTests"),
        .testTarget(name: "NastroMediaTests", dependencies: ["NastroMedia"], path: "Tests/NastroMediaTests"),
    ]
)
