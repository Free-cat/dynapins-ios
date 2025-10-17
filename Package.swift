// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DynamicPinning",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DynamicPinning",
            targets: ["DynamicPinning"]),
    ],
    dependencies: [
        .package(url: "https://github.com/airsidemobile/JOSESwift.git", from: "2.4.0"),
        .package(url: "https://github.com/datatheorem/TrustKit.git", from: "3.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "DynamicPinning",
            dependencies: ["JOSESwift", "TrustKit"]),
        .testTarget(
            name: "DynamicPinningTests",
            dependencies: ["DynamicPinning"]),
    ]
)
