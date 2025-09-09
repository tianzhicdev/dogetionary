// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DogetionaryApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(
            name: "DogetionaryApp",
            targets: ["DogetionaryApp"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DogetionaryApp",
            dependencies: [],
            path: "Sources/Dogetionary"),
    ]
)