// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RAWSelect",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RAWSelect",
            path: "Sources/RAWSelect"
        )
    ]
)
