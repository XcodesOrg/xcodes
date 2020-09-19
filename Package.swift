// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "xcodes",
    platforms: [
       .macOS(.v10_13)
    ],
    products: [
        .executable(name: "xcodes", targets: ["xcodes"]),
        .library(name: "XcodesKit", targets: ["XcodesKit"]),
        .library(name: "AppleAPI", targets: ["AppleAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nsomar/Guaka.git", .upToNextMinor(from: "0.4.0")),
        .package(url: "https://github.com/mxcl/Path.swift.git", .upToNextMinor(from: "0.16.0")),
        .package(url: "https://github.com/mxcl/Version.git", .upToNextMinor(from: "1.0.3")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMinor(from: "6.8.3")),
        .package(name: "PMKFoundation", url: "https://github.com/PromiseKit/Foundation.git", .upToNextMinor(from: "3.3.1")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMinor(from: "2.0.0")),
        .package(url: "https://github.com/mxcl/LegibleError.git", .upToNextMinor(from: "1.0.1")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMinor(from: "3.2.0")),
        .package(url: "https://github.com/AliSoftware/OHHTTPStubs", .upToNextMinor(from: "9.0.0")),
    ],
    targets: [
        .target(
            name: "xcodes",
            dependencies: [
                "Guaka", "XcodesKit"
            ]),
        .testTarget(
            name: "xcodesTests",
            dependencies: ["xcodes"]),
        .target(
            name: "XcodesKit",
            dependencies: [
                "AppleAPI", .product(name: "Path", package: "Path.swift"), "Version", "PromiseKit", "PMKFoundation", "SwiftSoup", "LegibleError", "KeychainAccess"
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
            dependencies: ["AppleAPI", .product(name: "OHHTTPStubsSwift", package: "OHHTTPStubs")],
            resources: [
                .copy("Fixtures"),
            ]),
    ]
)
