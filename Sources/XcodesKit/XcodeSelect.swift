import Foundation
import Path
import Version
import Rainbow
import XcodesKit

public func selectXcodeAsync(shouldPrint: Bool, pathOrVersion: String, directory: Path, fallbackToInteractive: Bool = true) async throws {
    let output = try await Current.shell.xcodeSelectPrintPath()

    if shouldPrint {
        if output.out.isEmpty == false {
            Current.logging.log(output.out)
        } else {
            Current.logging.log("No selected Xcode")
        }
        Current.shell.exit(0)
        return
    }

    let installedXcodes = Current.files.installedXcodes(directory)
    let selectionService = XcodeSelectionService(versionFile: XcodeVersionFileService(
        fileExists: { path in Current.files.fileExists(atPath: path) },
        contentsAtPath: { path in Current.files.contents(atPath: path) }
    ))

    switch selectionService.request(
        pathOrVersion: pathOrVersion,
        installedXcodes: installedXcodes,
        selectedXcodePath: output.out
    ) {
    case let .alreadySelectedVersion(version):
        Current.logging.log("Xcode \(version) is already selected".green)
        Current.shell.exit(0)
        return
    case let .selectInstalledXcode(installedXcode):
        let selectedOutput = try await selectXcodeAtPathAsync(installedXcode.path.string)
        Current.logging.log("Selected \(selectedOutput.out)".green)
        Current.shell.exit(0)
        return
    case .alreadySelectedPath:
        Current.logging.log("Xcode at path \(pathOrVersion) is already selected".green)
        Current.shell.exit(0)
        return
    case let .selectPath(pathToSelect):
        do {
            let selectedOutput = try await selectXcodeAtPathAsync(pathToSelect)
            Current.logging.log("Selected \(selectedOutput.out)".green)
            Current.shell.exit(0)
        } catch {
            guard fallbackToInteractive else { throw error }
            let selectedOutput = try await selectXcodeInteractivelyAsync(currentPath: output.out, directory: directory)
            Current.logging.log("Selected \(selectedOutput.out)".green)
            Current.shell.exit(0)
        }
    }
}

public func selectXcodeInteractivelyAsync(currentPath: String, directory: Path, shouldRetry: Bool) async throws -> ProcessOutput {
    if shouldRetry {
        while true {
            do {
                return try await selectXcodeInteractivelyAsync(currentPath: currentPath, directory: directory)
            } catch let error as XcodeSelectError {
                guard case .invalidIndex = error else { throw error }
                Current.logging.log("\(error.legibleLocalizedDescription)\n".red)
            }
        }
    } else {
        return try await selectXcodeInteractivelyAsync(currentPath: currentPath, directory: directory)
    }
}

public func chooseFromInstalledXcodesInteractivelyAsync(currentPath: String, directory: Path) async throws -> InstalledXcode {
    try chooseFromInstalledXcodesInteractivelySync(currentPath: currentPath, directory: directory)
}

private func chooseFromInstalledXcodesInteractivelySync(currentPath: String, directory: Path) throws -> InstalledXcode {
    let sortedInstalledXcodes = Current.files.installedXcodes(directory).sorted { $0.version < $1.version }

    Current.logging.log("Available Xcode versions:")

    sortedInstalledXcodes
        .enumerated()
        .forEach { index, installedXcode in
            var output = "\(index + 1)) \(installedXcode.version.appleDescriptionWithBuildIdentifier)"
            if currentPath.hasPrefix(installedXcode.path.string) {
                output += " (\("Selected".green))"
            }
            Current.logging.log(output)
        }

    let possibleSelectionNumberString = Current.shell.readLine(prompt: "Enter the number of the Xcode to select: ")
    do {
        return try XcodeSelectionService().installedXcode(
            fromSelection: possibleSelectionNumberString,
            installedXcodes: sortedInstalledXcodes
        )
    } catch let error as XcodeSelectionError {
        switch error {
        case let .invalidIndex(min, max, given):
            throw XcodeSelectError.invalidIndex(min: min, max: max, given: given)
        }
    }
}

public func selectXcodeInteractivelyAsync(currentPath: String, directory: Path) async throws -> ProcessOutput {
    let selectedXcode = try await chooseFromInstalledXcodesInteractivelyAsync(currentPath: currentPath, directory: directory)
    return try await selectXcodeAtPathAsync(selectedXcode.path.string)
}

public func selectXcodeAtPathAsync(_ pathString: String) async throws -> ProcessOutput {
    guard Current.files.fileExists(atPath: pathString) else {
        throw XcodeSelectError.invalidPath(pathString)
    }

    let passwordInput: @Sendable () async throws -> String = {
        Current.logging.log("xcodes requires superuser privileges to select an Xcode")
        guard let password = Current.shell.readSecureLine(prompt: "macOS User Password: ") else {
            throw XcodeInstaller.Error.missingSudoerPassword
        }
        return password + "\n"
    }

    let possiblePassword = try await Current.shell.authenticateSudoerIfNecessaryAsync(passwordInput: passwordInput)
    _ = try await Current.shell.xcodeSelectSwitch(possiblePassword, pathString)
    return try await Current.shell.xcodeSelectPrintPath()
}

public enum XcodeSelectError: LocalizedError {
    case invalidPath(String)
    case invalidIndex(min: Int, max: Int, given: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let pathString):
            return "Not a valid Xcode path: \(pathString)"
        case .invalidIndex(let min, let max, let given):
            return "Not a valid number. Expecting a whole number between \(min)-\(max), but given \(given ?? "nothing")."
        }
    }
}
