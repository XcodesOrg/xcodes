import Foundation
import PromiseKit
import PMKFoundation
import Path

typealias ProcessOutput = (status: Int32, out: Pipe, err: Pipe)

extension Process {
    @discardableResult
    static func run(_ executable: Path, _ arguments: String...) -> Promise<ProcessOutput> {
        return run(executable.url, arguments)
    }

    @discardableResult
    static func run(_ executable: URL, _ arguments: [String]) -> Promise<ProcessOutput> {
        let process = Process()
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.executableURL = executable
        process.arguments = arguments
        return process.launch(.promise).map { std in (process.terminationStatus, std.out, std.err) }
    }
}
