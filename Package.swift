// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "xcodes",
    products: [
        .executable(name: "xcodes", targets: ["xcodes"]),
        .library(name: "XcodesKit", targets: ["XcodesKit"]),
        .library(name: "AppleAPI", targets: ["AppleAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nsomar/Guaka.git", .upToNextMinor(from: "0.3.1")),
        .package(url: "https://github.com/mxcl/Path.swift.git", .upToNextMinor(from: "0.16.0")),
        .package(url: "https://github.com/mxcl/Version.git", .upToNextMinor(from: "1.0.3")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMinor(from: "6.8.3")),
        .package(url: "https://github.com/PromiseKit/Foundation.git", .upToNextMinor(from: "3.3.1")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMinor(from: "1.7.5")),
        .package(url: "https://github.com/mxcl/LegibleError.git", .upToNextMinor(from: "1.0.1")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMinor(from: "3.2.0"))
    ],
    targets: [
        .target(
            name: "xcodes",
            dependencies: [
                "Guaka", "XcodesKit", "KeychainAccess"
            ]),
        .testTarget(
            name: "xcodesTests",
            dependencies: ["xcodes"]),
        .target(
            name: "XcodesKit",
            dependencies: [
                "AppleAPI", "Path", "Version", "PromiseKit", "PMKFoundation", "SwiftSoup", "LegibleError"
            ]),
        .testTarget(
            name: "XcodesKitTests",
            dependencies: [
                "XcodesKit", "Version"
            ]),
        .target(
            name: "AppleAPI",
            dependencies: [
                "PromiseKit", "PMKFoundation"
            ]),
        .testTarget(
            name: "AppleAPITests",
            dependencies: ["AppleAPI"]),
    ]
)
