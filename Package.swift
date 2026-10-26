// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Canvas",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Canvas",
            path: "Sources/Canvas",
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
