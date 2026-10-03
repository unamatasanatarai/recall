// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "Recall",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "Recall", targets: ["Recall"])
    ],
    targets: [
        .executableTarget(
            name: "Recall",
            path: "Sources/Recall"
        ),
        .testTarget(
            name: "RecallTests",
            dependencies: ["Recall"],
            path: "Tests/RecallTests"
        )
    ]
)
