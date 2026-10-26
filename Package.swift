// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Expanse",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Expanse",
            path: "Sources/Expanse",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        )
    ]
)
