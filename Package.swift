// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Sobreiro",
    platforms: [
        .macOS(.v10_12),
        .iOS(.v10),
        .tvOS(.v10)
    ],
    products: [
        .library(
            name: "Sobreiro",
            targets: ["Sobreiro"]),
    ],
    targets: [
        .target(
            name: "Sobreiro",
            dependencies: []),
    ]
)
