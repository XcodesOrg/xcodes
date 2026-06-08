// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "xcodes",
    platforms: [
       .macOS(.v13),
       .iOS(.v17)
    ],
    products: [
        .executable(name: "xcodes", targets: ["xcodes"]),
        .library(name: "XcodesCLIKit", targets: ["XcodesCLIKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.1.4")),
        .package(url: "https://github.com/mxcl/Path.swift.git", from: "1.0.0"),
        .package(url: "https://github.com/mxcl/Version.git", .upToNextMinor(from: "1.0.3")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMinor(from: "2.0.0")),
        .package(url: "https://github.com/mxcl/LegibleError.git", .upToNextMinor(from: "1.0.1")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMinor(from: "3.2.0")),
        .package(url: "https://github.com/xcodereleases/data", revision: "fcf527b187817f67c05223676341f3ab69d4214d"),
        .package(url: "https://github.com/onevcat/Rainbow.git", .upToNextMinor(from: "3.2.0")),
        .package(path: "../XcodesLoginKit"),
        .package(path: "../XcodesKit")
    ],
    targets: [
        .executableTarget(
            name: "xcodes",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "XcodesCLIKit",
                .product(name: "XcodesKit", package: "XcodesKit")
            ]),
        .testTarget(
            name: "xcodesTests",
            dependencies: [
                "xcodes"
            ]),
        .target(
            name: "XcodesCLIKit",
            dependencies: [
                "KeychainAccess",
                "LegibleError",
                .product(name: "Path", package: "Path.swift"), 
                "SwiftSoup",
                "Unxip",
                "Version",
                .product(name: "XCModel", package: "data"),
                "XcodesLoginKit",
                .product(name: "XcodesKit", package: "XcodesKit"),
                "Rainbow"
            ],
            path: "Sources/XcodesKit"),
        .testTarget(
            name: "XcodesKitTests",
            dependencies: [
                "XcodesCLIKit",
                .product(name: "XcodesKit", package: "XcodesKit"),
                "Version"
            ],
            resources: [
                .copy("Fixtures"),
            ]),
        .target(name: "Unxip"),
    ]
)
