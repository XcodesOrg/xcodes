import Foundation

public struct Build: Equatable, CustomStringConvertible {
    
    let identifier: String
    
    /**
     E.g.:
     13E500a
     12E507
     7B85
     */
    init?(identifier: String) {
        let nsrange = NSRange(identifier.startIndex..<identifier.endIndex, in: identifier)
        let pattern = "^\\d+[A-Z]\\d+[a-z]*$"
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            regex.firstMatch(in: identifier, options: [], range: nsrange) != nil else {
            return nil
        }
        self.identifier = identifier
    }
    
    public var description: String { identifier }
}
