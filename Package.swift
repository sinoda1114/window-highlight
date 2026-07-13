// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WindowHighlight",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WindowHighlight", targets: ["WindowHighlight"])
    ],
    targets: [
        .executableTarget(
            name: "WindowHighlight",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
