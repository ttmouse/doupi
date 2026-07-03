// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoupiViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DoupiViewer",
            resources: [.copy("Resources")]
        )
    ]
)
