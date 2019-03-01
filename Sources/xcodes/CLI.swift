import Foundation

/**
 Like `readLine()`, but doesn't echo the user's input to the screen.

 - Parameter prompt: Prompt printed on the line preceding user input
 - Parameter maximumLength: The maximum length to read, in bytes

 - Returns: The entered password, or nil if an error occurred.

 Buffer is zeroed after use.

 - SeeAlso: [readpassphrase man page](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/readpassphrase.3.html)
 */
func readSecureLine(prompt: String, maximumLength: Int = 8192) -> String? {
    let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: maximumLength)
    buffer.initialize(repeating: 0, count: maximumLength)
    defer {
        buffer.deinitialize(count: maximumLength)
        buffer.initialize(repeating: 0, count: maximumLength)
        buffer.deinitialize(count: maximumLength)
        buffer.deallocate()
    }

    guard let passwordData = readpassphrase(prompt, buffer, maximumLength, 0) else {
        return nil
    }

    return String(validatingUTF8: passwordData)
}

func readLine(prompt: String) -> String? {
    print(prompt, terminator: "")
    return readLine()
}

func env(_ key: String) -> String? {
    return ProcessInfo.processInfo.environment[key]
}
