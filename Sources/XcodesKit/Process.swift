import Foundation
import PromiseKit
import PMKFoundation
import Path

typealias ProcessOutput = (status: Int32, out: String, err: String)

extension Process {
    @discardableResult
    static func run(_ executable: Path, workingDirectory: URL? = nil, _ arguments: String...) -> Promise<ProcessOutput> {
        return run(executable.url, workingDirectory: workingDirectory, arguments)
    }

    @discardableResult
    static func run(_ executable: URL, workingDirectory: URL? = nil, _ arguments: [String]) -> Promise<ProcessOutput> {
        let process = Process()
        process.currentDirectoryURL = workingDirectory ?? executable.deletingLastPathComponent()
        process.executableURL = executable
        process.arguments = arguments
        return process.launch(.promise).map { std in 
            let output = String(data: std.out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: std.err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, output, error)
        }
    }
}
