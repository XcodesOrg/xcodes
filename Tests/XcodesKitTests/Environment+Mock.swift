@testable import XcodesCLIKit
import Foundation
import XcodesKit

func syncXcodesKitMocks() {
    configureXcodesKitFileContents { XcodesCLIKit.Current.files.contents(atPath: $0) }
    configureXcodesKitArchs { _ in Shell.processOutputMock }
}

extension Environment {
    static var mock: Environment {
        Environment(
            shell: .mock,
            files: .mock,
            network: .mock,
            logging: .mock,
            keychain: .mock
        )
    }
}

extension Shell {
    static let processOutputMock: ProcessOutput = (0, "", "")

    static var mock: Shell {
        Shell(
            unxip: { _ in Shell.processOutputMock },
            mountDmg: { _ in Shell.processOutputMock },
            unmountDmg: { _ in Shell.processOutputMock },
            expandPkg: { _, _ in Shell.processOutputMock },
            createPkg: { _, _ in Shell.processOutputMock },
            installPkg: { _, _ in Shell.processOutputMock },
            installRuntimeImage: { _ in Shell.processOutputMock },
            spctlAssess: { _ in Shell.processOutputMock },
            codesignVerify: { _ in Shell.processOutputMock },
            devToolsSecurityEnable: { _ in Shell.processOutputMock },
            addStaffToDevelopersGroup: { _ in Shell.processOutputMock },
            acceptXcodeLicense: { _, _ in Shell.processOutputMock },
            runFirstLaunch: { _, _ in Shell.processOutputMock },
            buildVersion: { Shell.processOutputMock },
            xcodeBuildVersion: { _ in Shell.processOutputMock },
            archs: { _ in Shell.processOutputMock },
            getUserCacheDir: { Shell.processOutputMock },
            touchInstallCheck: { _, _, _ in Shell.processOutputMock },
            installedRuntimes: { Shell.processOutputMock },
            validateSudoAuthentication: { Shell.processOutputMock },
            // Deliberately using real implementation of authenticateSudoerIfNecessary since it depends on others that can be mocked
            xcodeSelectPrintPath: { Shell.processOutputMock },
            xcodeSelectSwitch: { _, _ in Shell.processOutputMock },
            isRoot: { true },
            readLine: { _ in return nil },
            readSecureLine: { _, _ in return nil },
            env: { _ in nil },
            exit: { _ in },
            isatty: { true }
        )
    }
}

extension Files {
    static var mock: Files {
        Files(
            fileExistsAtPath: { _ in return true },
            attributesOfItemAtPath: { _ in [:] },
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
            write: { _, _ in },
            removeItem: { _ in },
            trashItem: { _ in return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash") },
            createFile: { _, _, _ in return true },
            createDirectory: { _, _, _ in },
            contentsOfDirectory: { _ in [] },
            installedXcodes: { _ in [] }
        )
    }
}

extension Network {
    static var mock: Network {
        Network(
            loadData: { urlRequest in
                return (
                    data: Data(),
                    response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            },
            downloadTask: { url, saveLocation, _ in
                return (
                    Progress(),
                    Task {
                        (saveLocation, HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                    }
                )
            },
            validateSession: {},
            login: { _, _ in }
        )
    }
}

extension Logging {
    static var mock: Logging {
        Logging(
            log: { print($0) }
        )
    }
}

extension Keychain {
    static var mock: Keychain {
        Keychain(
            getString: { _ in return nil },
            set: { _, _ in },
            remove: { _ in }
        )
    }
}
