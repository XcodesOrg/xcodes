import Foundation
import PromiseKit
import PMKFoundation
import Path

public typealias ProcessOutput = (status: Int32, out: String, err: String)

extension Process {
    @discardableResult
    static func sudo(password: String? = nil, _ executable: Path, workingDirectory: URL? = nil, _ arguments: String...) -> Promise<ProcessOutput> {
        var arguments = [executable.string] + arguments
        if password != nil {
            arguments.insert("-S", at: 0)
        } 
        return run(Path.root.usr.bin.sudo.url, workingDirectory: workingDirectory, input: password, arguments)
    }

    @discardableResult
    static func run(_ executable: Path, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) -> Promise<ProcessOutput> {
        return run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }

    @discardableResult
    static func run(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) -> Promise<ProcessOutput> {
        return Promise { seal in
            let process = Process()
            process.currentDirectoryURL = workingDirectory ?? executable.deletingLastPathComponent()
            process.executableURL = executable
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            var output = Data()
            var error = Data()
            
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    output.append(data)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    error.append(data)
                }
            }

            if let input = input {
                let inputPipe = Pipe()
                process.standardInput = inputPipe
                if let inputData = input.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(inputData)
                }
                inputPipe.fileHandleForWriting.closeFile()
            }

            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                seal.reject(error)
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let outputString = String(data: output, encoding: .utf8) ?? ""
                let errorString = String(data: error, encoding: .utf8) ?? ""
                seal.fulfill((process.terminationStatus, outputString, errorString))
            }
        }
    }
}
