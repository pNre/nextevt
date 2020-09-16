// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "NextEvt",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NextEvt",
            dependencies: [],
            path: "NextEvt"
        )
    ]
)
