// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GitHubActionWidget",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GitHubActionWidget",
            path: "Sources/GitHubActionWidget"
        )
    ]
)
