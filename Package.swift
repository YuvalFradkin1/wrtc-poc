// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "wrtc-poc",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "wrtc-poc",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
