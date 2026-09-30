// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpiderBuddy",
    platforms: [.macOS(.v13)],
    dependencies: [
        // In-app updates (Check for Updates…, automatic checks)
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "SpiderBuddy",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SpiderBuddy",
            // Sparkle.framework is bundled into Contents/Frameworks by build.sh
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
