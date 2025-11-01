// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "xcodes",
    platforms: [
       .macOS(.v10_15)
    ],
    products: [
        .executable(name: "xcodes", targets: ["xcodes"]),
        .library(name: "XcodesKit", targets: ["XcodesKit"]),
        .library(name: "AppleAPI", targets: ["AppleAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.1.4")),
        .package(url: "https://github.com/mxcl/Path.swift.git", .upToNextMinor(from: "0.16.0")),
        .package(url: "https://github.com/mxcl/Version.git", .upToNextMinor(from: "1.0.3")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMinor(from: "6.22.1")),
        .package(url: "https://github.com/PromiseKit/Foundation.git", .upToNextMinor(from: "3.4.0")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMinor(from: "2.0.0")),
        .package(url: "https://github.com/mxcl/LegibleError.git", .upToNextMinor(from: "1.0.1")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMinor(from: "3.2.0")),
        .package(url: "https://github.com/xcodereleases/data", revision: "fcf527b187817f67c05223676341f3ab69d4214d"),
        .package(url: "https://github.com/onevcat/Rainbow.git", .upToNextMinor(from: "3.2.0")),
        .package(url: "https://github.com/jpsim/Yams", .upToNextMinor(from: "5.0.1")),
        .package(url: "https://github.com/xcodesOrg/swift-srp", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "xcodes",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "XcodesKit"
            ]),
        .testTarget(
            name: "xcodesTests",
            dependencies: [
                "xcodes"
            ]),
        .target(
            name: "XcodesKit",
            dependencies: [
                "AppleAPI", 
                "KeychainAccess",
                "LegibleError",
                .product(name: "Path", package: "Path.swift"), 
                "PromiseKit",
                .product(name: "PMKFoundation", package: "Foundation"),
                "SwiftSoup",
                "Version",
                .product(name: "XCModel", package: "data"),
                "Rainbow",
                "Yams"
            ],
            resources: [
                .copy("Resources/unxip"),
            ]),
        .testTarget(
            name: "XcodesKitTests",
            dependencies: [
                "XcodesKit",
                "Version"
            ],
            resources: [
                .copy("Fixtures"),
            ]),
        .target(
            name: "AppleAPI",
            dependencies: [
                "PromiseKit",
                .product(name: "PMKFoundation", package: "Foundation"),
                "Rainbow",
                .product(name: "SRP", package: "swift-srp")
            ]),
        .testTarget(
            name: "AppleAPITests",
            dependencies: [
                "AppleAPI"
            ],
            resources: [
                .copy("Fixtures"),
            ]),
    ]
)
