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
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "0.3.0")),
        .package(url: "https://github.com/mxcl/Path.swift.git", .upToNextMinor(from: "0.16.0")),
        .package(url: "https://github.com/mxcl/Version.git", .upToNextMinor(from: "1.0.3")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMinor(from: "6.8.3")),
        .package(name: "PMKFoundation", url: "https://github.com/PromiseKit/Foundation.git", .upToNextMinor(from: "3.3.1")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMinor(from: "2.0.0")),
        .package(url: "https://github.com/mxcl/LegibleError.git", .upToNextMinor(from: "1.0.1")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMinor(from: "3.2.0")),
        .package(name: "XcodeReleases", url: "https://github.com/xcodereleases/data", .revision("b47228c688b608e34b3b84079ab6052a24c7a981")),
        .package(url: "https://github.com/onevcat/Rainbow.git", .upToNextMinor(from: "3.2.0")),
    ],
    targets: [
        .target(
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
                "PMKFoundation", 
                "SwiftSoup",
                "Version", 
                .product(name: "XCModel", package: "XcodeReleases"),
                "Rainbow",
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
                "PMKFoundation",
                "Rainbow",
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
