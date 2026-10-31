// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Expanse",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Expanse",
            path: "Sources/Expanse",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Lets the tests reach private code (@_private import); debug builds only.
                .unsafeFlags(["-Xfrontend", "-enable-private-imports"], .when(configuration: .debug)),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "ExpanseTests",
            dependencies: ["Expanse"],
            path: "Tests/ExpanseTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
