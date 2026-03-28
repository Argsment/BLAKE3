// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BLAKE3",
    products: [
        .library(name: "BLAKE3", targets: ["BLAKE3"]),
    ],
    targets: [
        .target(name: "BLAKE3", path: "Sources/BLAKE3"),
        .testTarget(name: "BLAKE3Tests", dependencies: ["BLAKE3"], path: "Tests/BLAKE3Tests"),
    ]
)
