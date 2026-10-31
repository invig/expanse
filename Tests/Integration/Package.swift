// swift-tools-version: 6.0
import PackageDescription

// The end-to-end regression tests (docs/regression): an app that drives a running development
// build of Expanse with real windows, links and input. Built and run by scripts/integration.sh.
let package = Package(
    name: "ExpanseIntegration",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ExpanseIntegration",
            path: "Sources/ExpanseIntegration",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
