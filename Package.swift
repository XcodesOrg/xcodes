// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "xcodes",
    dependencies: [
        .package(url: "https://github.com/nsomar/Guaka.git", .upToNextMinor(from: "0.3.1")),
        .package(url: "https://github.com/mxcl/Path.swift.git", .upToNextMinor(from: "0.16.0")),
        .package(url: "https://github.com/mxcl/Version.git", .upToNextMinor(from: "1.0.3")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMinor(from: "6.8.3")),
        .package(url: "https://github.com/PromiseKit/Foundation.git", .upToNextMinor(from: "3.3.1"))
    ],
    targets: [
        .target(
            name: "xcodes",
            dependencies: [
                "Guaka", "Path", "Version", "PromiseKit", "PMKFoundation"
            ]),
        .testTarget(
            name: "xcodesTests",
            dependencies: ["xcodes"]),
    ]
)
