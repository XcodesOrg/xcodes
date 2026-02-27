import XCTest
import Foundation
import Version
import PromiseKit
import Path
@testable import XcodesKit

final class XcodeForceReinstallRollbackTests: XCTestCase {
    var xcodeInstaller: XcodeInstaller!

    override class func setUp() {
        super.setUp()
        PromiseKit.conf.Q.map = nil
        PromiseKit.conf.Q.return = nil
    }

    override func setUp() {
        Current = .mock
        xcodeInstaller = XcodeInstaller(xcodeList: XcodeList(), sessionService: AppleSessionService(configuration: Configuration()))
    }

    func test_forceReinstall_restoresPreviousInstallationOnFailure() {
        let version = Version("26.0.0")!
        let archivePath = Path("/tmp/Xcode-26.0.0.xip")!
        let destination = Path("/Applications")!
        let installedAppPath = destination.join("Xcode-\(version.descriptionWithoutBuildMetadata).app")
        let expectedError = NSError(domain: "XcodeForceReinstallRollbackTests", code: 420)

        var existingPaths = Set([installedAppPath.string])
        var moveOperations = [(from: String, to: String)]()

        Current.files.installedXcodes = { _ in
            [InstalledXcode(path: installedAppPath, version: version)]
        }
        Current.files.fileExistsAtPath = { existingPaths.contains($0) }
        Current.files.moveItem = { source, destination in
            moveOperations.append((source.path, destination.path))
            guard existingPaths.contains(source.path) else {
                throw NSError(domain: "XcodeForceReinstallRollbackTests", code: 100)
            }
            existingPaths.remove(source.path)
            existingPaths.insert(destination.path)
        }
        Current.files.removeItem = { url in
            existingPaths.remove(url.path)
        }
        Current.shell.unxip = { _ in
            Promise(error: expectedError)
        }

        let expectation = expectation(description: "force reinstall failure restores previous app")

        xcodeInstaller.install(.path(version.appleDescription, archivePath),
                               dataSource: .xcodeReleases,
                               downloader: .urlSession,
                               destination: destination,
                               emptyTrash: false,
                               noSuperuser: true,
                               forceReinstall: true)
        .done { _ in
            XCTFail("Expected install to fail.")
        }
        .catch { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, expectedError.domain)
            XCTAssertEqual(nsError.code, expectedError.code)

            XCTAssertEqual(moveOperations.count, 2)
            XCTAssertEqual(moveOperations.first?.from, installedAppPath.string)
            XCTAssertEqual(moveOperations.last?.from, moveOperations.first?.to)
            XCTAssertEqual(moveOperations.last?.to, installedAppPath.string)
            XCTAssertTrue(existingPaths.contains(installedAppPath.string))
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func test_forceReinstall_cleansBackupOnSuccess() {
        let version = Version("26.0.0")!
        let archivePath = Path("/tmp/Xcode-26.0.0.xip")!
        let unpackedAppPath = Path("/tmp/Xcode.app")!
        let destination = Path("/Applications")!
        let installedAppPath = destination.join("Xcode-\(version.descriptionWithoutBuildMetadata).app")
        let installedXcode = InstalledXcode(path: installedAppPath, version: version)

        var existingPaths = Set([installedAppPath.string, archivePath.string, unpackedAppPath.string])
        var moveOperations = [(from: String, to: String)]()
        var trashedPaths = [String]()

        Current.files.installedXcodes = { _ in
            [InstalledXcode(path: installedAppPath, version: version)]
        }
        Current.files.fileExistsAtPath = { existingPaths.contains($0) }
        Current.files.moveItem = { source, destination in
            moveOperations.append((source.path, destination.path))
            guard existingPaths.contains(source.path) else {
                throw NSError(domain: "XcodeForceReinstallRollbackTests", code: 101)
            }
            existingPaths.remove(source.path)
            existingPaths.insert(destination.path)
        }
        Current.files.trashItem = { url in
            trashedPaths.append(url.path)
            existingPaths.remove(url.path)
            return URL(fileURLWithPath: "/tmp/.Trash/\(url.lastPathComponent)")
        }
        Current.shell.unxip = { _ in
            Promise.value(Shell.processOutputMock)
        }
        Current.shell.codesignVerify = { _ in
            Promise.value(
                ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                        """
                )
            )
        }

        let expectation = expectation(description: "force reinstall success cleans backup")

        xcodeInstaller.install(.path(version.appleDescription, archivePath),
                               dataSource: .xcodeReleases,
                               downloader: .urlSession,
                               destination: destination,
                               emptyTrash: false,
                               noSuperuser: true,
                               forceReinstall: true)
        .done { result in
            XCTAssertEqual(result.path, installedXcode.path)

            XCTAssertEqual(moveOperations.count, 2)
            XCTAssertEqual(moveOperations[0].from, installedAppPath.string)
            XCTAssertEqual(moveOperations[1].from, unpackedAppPath.string)
            XCTAssertEqual(moveOperations[1].to, installedAppPath.string)

            let backupPath = moveOperations[0].to
            XCTAssertEqual(Set(trashedPaths), Set([archivePath.string, backupPath]))
            XCTAssertTrue(existingPaths.contains(installedAppPath.string))
            XCTAssertFalse(existingPaths.contains(backupPath))
            expectation.fulfill()
        }
        .catch { error in
            XCTFail("Expected install to succeed, got \(error)")
        }

        waitForExpectations(timeout: 1.0)
    }
}
