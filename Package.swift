// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ConferenceDeadline",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ConferenceDeadline",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ConferenceDeadlineTests",
            dependencies: ["ConferenceDeadline"]
        )
    ]
)
