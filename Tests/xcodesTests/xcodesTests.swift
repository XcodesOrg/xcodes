import XCTest
import class Foundation.Bundle
import Foundation

final class xcodesTests: XCTestCase {
    struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    func test_installArchitecture_requiresExplicitVersion() throws {
        let result = try runXcodes(["install", "--latest", "--architecture", "apple-silicon", "--no-color"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("--architecture is currently supported only when installing an explicit Xcode version."))
    }

    func test_installArchitecture_requiresXcodeReleasesDataSource_evenWithForceReinstall() throws {
        let result = try runXcodes(["install", "26.0", "--architecture", "apple-silicon", "--force-reinstall", "--data-source", "apple", "--no-color"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("--architecture requires --data-source xcodeReleases, but got apple."))
    }

    func test_installHelp_containsArchitectureAndForceReinstallFlags() throws {
        let result = try runXcodes(["install", "--help"])

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("--architecture"))
        XCTAssertTrue(result.stdout.contains("--force-reinstall"))
    }

    /// Returns path to the built products directory.
    var productsDirectory: URL {
      #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("couldn't find the products directory")
      #else
        return Bundle.main.bundleURL
      #endif
    }

    private func runXcodes(_ arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("xcodes")
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
