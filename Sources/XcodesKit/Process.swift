import Foundation
import Path
import XcodesKit

public typealias ProcessOutput = XcodesKit.ProcessOutput
public typealias ProcessExecutionError = XcodesKit.ProcessExecutionError

extension Process {
    @discardableResult
    static func sudoAsync<P: Pathish>(password: String? = nil, _ executable: P, workingDirectory: URL? = nil, _ arguments: String...) async throws -> ProcessOutput {
        var arguments = [executable.string] + arguments
        if password != nil {
            arguments.insert("-S", at: 0)
        }
        return try await runAsync(Path.root.usr.bin.sudo.url, workingDirectory: workingDirectory, input: password, arguments)
    }

    @discardableResult
    static func runAsync<P: Pathish>(_ executable: P, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) async throws -> ProcessOutput {
        try await runAsync(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }

    @discardableResult
    static func runAsync(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) async throws -> ProcessOutput {
        try await XcodesProcess.run(executable, workingDirectory: workingDirectory, input: input, arguments)
    }
}
