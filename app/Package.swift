// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpiderBuddy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SpiderBuddy", path: "Sources/SpiderBuddy"),
    ]
)
