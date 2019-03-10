@testable import XcodesKit
import Foundation
import PromiseKit

extension Environment {
    static var mock = Environment(
        shell: .mock,
        files: .mock
    )
}

extension Shell {
    static var processOutputMock: ProcessOutput = (0, "", "")

    static var mock = Shell(
        unxip: { _ in return Promise.value(Shell.processOutputMock) },
        spctlAssess: { _ in return Promise.value(Shell.processOutputMock) },
        codesignVerify: { _ in return Promise.value(Shell.processOutputMock) },
        validateSudoAuthentication: { return Promise.value(Shell.processOutputMock) },
        devToolsSecurityEnable: { _ in return Promise.value(Shell.processOutputMock) },
        addStaffToDevelopersGroup: { _ in return Promise.value(Shell.processOutputMock) },
        acceptXcodeLicense: { _, _ in return Promise.value(Shell.processOutputMock) },
        runFirstLaunch: { _, _ in return Promise.value(Shell.processOutputMock) },
        buildVersion: { return Promise.value(Shell.processOutputMock) },
        xcodeBuildVersion: { _ in return Promise.value(Shell.processOutputMock) },
        getUserCacheDir: { return Promise.value(Shell.processOutputMock) },
        touchInstallCheck: { _, _, _ in return Promise.value(Shell.processOutputMock) }
    )
}

extension Files {
    static var mock = Files(
        fileExistsAtPath: { _ in return true },
        moveItem: { _, _ in return },
        contentsAtPath: { _ in 
            let url = URL(fileURLWithPath: "Stub.plist", relativeTo: URL(fileURLWithPath: #file).deletingLastPathComponent())
            return try? Data(contentsOf: url)
        },
        removeItem: { _ in }
    )
}