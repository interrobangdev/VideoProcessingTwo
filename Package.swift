// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VideoProcessingTwo",
    platforms: [
        .iOS(.v15),
        .macOS(.v11),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "VideoProcessingTwo",
            targets: ["VideoProcessingTwo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/JuniperPhoton/CIMetalCompilerPlugin", from: "0.11.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "VideoProcessingTwo",
            path: "Sources",
            exclude: [
                "Shaders/"
            ],
            plugins: [
                .plugin(name: "CIMetalCompilerPlugin", package: "CIMetalCompilerPlugin")
            ]),
        .testTarget(
            name: "VideoProcessingTwoTests",
            dependencies: ["VideoProcessingTwo"]),
    ]
)
