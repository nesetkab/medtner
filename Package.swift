// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Medtner",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Medtner",
            path: "Sources/Medtner",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        )
    ]
)
