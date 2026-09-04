// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Espacio",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Espacio",
            path: "Sources/Espacio",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-Ounchecked"], .when(configuration: .release)),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreServices"),
                .linkedFramework("QuickLookUI"),
            ]
        )
    ]
)
