@testable import XcodesKit
import Foundation
import PromiseKit

extension Environment {
    static var mock = Environment(
        shell: .mock,
        files: .mock,
        network: .mock,
        logging: .mock,
        keychain: .mock
    )
}

extension Shell {
    static var processOutputMock: ProcessOutput = (0, "", "")

    static var mock = Shell(
        unxip: { _ in return Promise.value(Shell.processOutputMock) },
        spctlAssess: { _ in return Promise.value(Shell.processOutputMock) },
        codesignVerify: { _ in return Promise.value(Shell.processOutputMock) },
        devToolsSecurityEnable: { _ in return Promise.value(Shell.processOutputMock) },
        addStaffToDevelopersGroup: { _ in return Promise.value(Shell.processOutputMock) },
        acceptXcodeLicense: { _, _ in return Promise.value(Shell.processOutputMock) },
        runFirstLaunch: { _, _ in return Promise.value(Shell.processOutputMock) },
        buildVersion: { return Promise.value(Shell.processOutputMock) },
        xcodeBuildVersion: { _ in return Promise.value(Shell.processOutputMock) },
        getUserCacheDir: { return Promise.value(Shell.processOutputMock) },
        touchInstallCheck: { _, _, _ in return Promise.value(Shell.processOutputMock) },
        validateSudoAuthentication: { return Promise.value(Shell.processOutputMock) },
        // Deliberately using real implementation of authenticateSudoerIfNecessary since it depends on others that can be mocked
        xcodeSelectPrintPath: { return Promise.value(Shell.processOutputMock) },
        xcodeSelectSwitch: { _, _ in return Promise.value(Shell.processOutputMock) },
        readLine: { _ in return nil },
        readSecureLine: { _, _ in return nil },
        env: { _ in nil },
        exit: { _ in }
    )
}

extension Files {
    static var mock = Files(
        fileExistsAtPath: { _ in return true },
        moveItem: { _, _ in return },
        contentsAtPath: { path in
            if path.contains("Info.plist") {
                let url = Bundle.module.url(forResource: "Stub-0.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path.contains("version.plist") {
                let url = Bundle.module.url(forResource: "Stub.version", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else {
                return nil
            }
        },
        removeItem: { _ in },
        trashItem: { _ in return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash") },
        createFile: { _, _, _ in return true },
        createDirectory: { _, _, _ in },
        installedXcodes: { [] }
    )
}

extension Network {
    static var mock = Network(
        dataTask: { url in return Promise.value((data: Data(), response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)) },
        downloadTask: { url, saveLocation, _ in return (Progress(), Promise.value((saveLocation, HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))) },
        validateSession: { Promise() },
        login: { _, _ in Promise() }
    )
}

extension Logging {
    static var mock = Logging(
        log: { print($0) }
    )
}

extension Keychain {
    static var mock = Keychain(
        getString: { _ in return nil },
        set: { _, _ in },
        remove: { _ in }
    )
}
