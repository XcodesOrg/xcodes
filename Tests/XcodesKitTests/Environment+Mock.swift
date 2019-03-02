@testable import XcodesKit
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
        devToolsSecurityEnable: { return Promise.value(Shell.processOutputMock) },
        addStaffToDevelopersGroup: { return Promise.value(Shell.processOutputMock) },
        acceptXcodeLicense: { _ in return Promise.value(Shell.processOutputMock) },
        runFirstLaunch: { _ in return Promise.value(Shell.processOutputMock) },
        buildVersion: { return Promise.value(Shell.processOutputMock) },
        xcodeBuildVersion: { _ in return Promise.value(Shell.processOutputMock) },
        getUserCacheDir: { return Promise.value(Shell.processOutputMock) },
        touchInstallCheck: { _, _, _ in return Promise.value(Shell.processOutputMock) }
    )
}

extension Files {
    static var mock = Files(
        fileExistsAtPath: { _ in return true },
        moveItem: { _, _ in return }
    )
}