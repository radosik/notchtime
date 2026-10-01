// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchTime",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchTime", targets: ["NotchTime"])
    ],
    targets: [
        .target(
            name: "NotchTimeCore",
            path: "Sources/NotchTimeCore"
        ),
        .executableTarget(
            name: "NotchTime",
            dependencies: ["NotchTimeCore"],
            path: "Sources/NotchTime"
        ),
        .testTarget(
            name: "NotchTimeCoreTests",
            dependencies: ["NotchTimeCore"],
            path: "Tests/NotchTimeCoreTests"
        )
    ]
)
