@testable import AppleAPI
import Foundation
import PromiseKit

extension Environment {
    static var mock = Environment(
        shell: .mock,
        network: .mock,
        logging: .mock
    )
}

extension Shell {
    static var mock = Shell(
        readLine: { _ in return nil }
    )
}

extension Network {
    static var mock = Network(
        dataTask: { url in return Promise.value((data: Data(), response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)) }
    )
}

extension Logging {
    static var mock = Logging(
        log: { print($0) }
    )
}
