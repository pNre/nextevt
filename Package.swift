// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "NextEvt",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "NextEvt",
            dependencies: [
                "LaunchAtLogin"
            ],
            path: "NextEvt"
        )
    ]
)
