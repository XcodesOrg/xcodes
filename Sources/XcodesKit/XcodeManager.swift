import Foundation
import Path
import Version
import PromiseKit
import PMKFoundation
import SwiftSoup
import AppleAPI

public final class XcodeManager {
    public let client = AppleAPI.Client()
    public let installer = XcodeInstaller()

    public init() {
        try? loadCachedAvailableXcodes()
        try? loadConfiguration()
    }

    public var installedXcodes: [InstalledXcode] {
        let results = try! Path.root.join("Applications").ls().filter { entry in
            guard entry.kind == .directory && entry.path.extension == "app" && !entry.path.isSymlink else { return false }
            let infoPlistPath = entry.path.join("Contents").join("Info.plist")
            let infoPlist = try! PropertyListDecoder().decode(InfoPlist.self, from: try! Data(contentsOf: infoPlistPath.url))
            return infoPlist.bundleID == "com.apple.dt.Xcode"
        }
        let installedXcodes = results.map { $0.path }.compactMap(InstalledXcode.init)
        return installedXcodes
    }

    public private(set) var availableXcodes: [Xcode] = []

    public private(set) var configuration = Configuration(defaultUsername: nil)

    public var shouldUpdate: Bool {
        return availableXcodes.isEmpty
    }

    public func update() -> Promise<[Xcode]> {
        return when(fulfilled: releasedXcodes(), prereleaseXcodes())
            .map { availableXcodes, prereleaseXcodes in
                let xcodes = availableXcodes + prereleaseXcodes
                self.availableXcodes = xcodes
                try? self.cacheAvailableXcodes(xcodes)
                return xcodes
            }
    }

    public func downloadXcode(_ xcode: Xcode, progressChanged: @escaping (Progress) -> Void) -> Promise<URL> {
        let destination = XcodeManager.applicationSupportPath/"Xcode-\(xcode.version).\(xcode.filename.suffix(fromLast: "."))"
        let resumeDataPath = XcodeManager.applicationSupportPath/"Xcode-\(xcode.version).resumedata"
        let persistedResumeData = Current.files.contents(atPath: resumeDataPath.string)
        
        return attemptResumableTask(maximumRetryCount: 3) { resumeData in
            let (progress, promise) = self.client.session.downloadTask(.promise,
                                                                       with: xcode.url,
                                                                       to: destination.url,
                                                                       resumingWith: resumeData ?? persistedResumeData)
            progressChanged(progress)
            return promise.map { $0.saveLocation }
        }
        .tap { result in
            self.persistOrCleanUpResumeData(at: resumeDataPath, for: result)
        }
    }

    public func saveUsername(_ username: String) {
        self.configuration = Configuration(defaultUsername: username)
        try? saveConfiguration(self.configuration)
    }
}

extension XcodeManager {
    private static let applicationSupportPath = Path.applicationSupport/"com.robotsandpencils.xcodes"
    private static let cacheFilePath = applicationSupportPath/"available-xcodes.json"
    private static let configurationFilePath = applicationSupportPath/"configuration.json"

    /// Migrates any application support files from Xcodes < v0.4 if application support files from >= v0.4 don't exist
    public static func migrateApplicationSupportFiles() {
        let oldApplicationSupportPath = Path.applicationSupport/"ca.brandonevans.xcodes"

        if Current.files.fileExistsAtPath(oldApplicationSupportPath.string) {
            if Current.files.fileExistsAtPath(applicationSupportPath.string) {
                print("Removing old support files...")
                try? Current.files.removeItem(oldApplicationSupportPath.url)
                print("Done")
            }
            else {
                print("Migrating old support files...")
                try? Current.files.moveItem(oldApplicationSupportPath.url, applicationSupportPath.url)
                print("Done")
            }
        }
    }

    private func loadCachedAvailableXcodes() throws {
        let data = try Data(contentsOf: XcodeManager.cacheFilePath.url)
        let xcodes = try JSONDecoder().decode([Xcode].self, from: data)
        self.availableXcodes = xcodes
    }

    private func cacheAvailableXcodes(_ xcodes: [Xcode]) throws {
        let data = try JSONEncoder().encode(xcodes)
        try FileManager.default.createDirectory(at: XcodeManager.cacheFilePath.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: XcodeManager.cacheFilePath.url)
    }

    private func loadConfiguration() throws {
        let data = try Data(contentsOf: XcodeManager.configurationFilePath.url)
        self.configuration = try JSONDecoder().decode(Configuration.self, from: data)
    }

    private func saveConfiguration(_ configuration: Configuration) throws {
        let data = try JSONEncoder().encode(configuration)
        try FileManager.default.createDirectory(at: XcodeManager.configurationFilePath.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: XcodeManager.configurationFilePath.url)
    }
}

extension XcodeManager {
    private func releasedXcodes() -> Promise<[Xcode]> {
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            client.session.dataTask(.promise, with: URLRequest.downloads)
        }
        .map { (data, response) -> [Xcode] in
            struct Downloads: Decodable {
                let downloads: [Download]
            }

            let downloads = try JSONDecoder().decode(Downloads.self, from: data)
            let xcodes = downloads
                .downloads
                .filter { $0.name.range(of: "^Xcode [0-9]", options: .regularExpression) != nil }
                .compactMap { download -> Xcode? in
                    let urlPrefix = "https://developer.apple.com/devcenter/download.action?path="
                    guard 
                        let xcodeFile = download.files.first(where: { $0.remotePath.hasSuffix("dmg") || $0.remotePath.hasSuffix("xip") }),
                        let url = URL(string: urlPrefix + xcodeFile.remotePath),
                        let versionString = download.name.replacingOccurrences(of: "Xcode ", with: "").split(separator: " ").map(String.init).first,
                        let version = Version(tolerant: versionString)
                    else { return nil }

                    return Xcode(version: version, url: url, filename: String(xcodeFile.remotePath.suffix(fromLast: "/")))
                }
            return xcodes
        }
    }

    private func prereleaseXcodes() -> Promise<[Xcode]> {
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            client.session.dataTask(.promise, with: URLRequest.download)
        }
        .map { (data, response) -> [Xcode] in
            let body = String(data: data, encoding: .utf8)!
            let document = try SwiftSoup.parse(body)

            guard 
                let versionString = try document.select("h2:containsOwn(Xcode)").first()?.text(),
                let version = Version(xcodeVersion: versionString),
                let path = try document.select(".direct-download[href*=xip]").first()?.attr("href"),
                let url = URL(string: "https://developer.apple.com" + path)
            else { return [] }

            let filename = String(path.suffix(fromLast: "/"))

            return [Xcode(version: version, url: url, filename: filename)]
        }
    }
    
    private func persistOrCleanUpResumeData<T>(at path: Path, for result: Result<T>) {
        switch result {
        case .fulfilled:
            try? Current.files.removeItem(at: path.url)
        case .rejected(let error):
            guard let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data else { return }
            Current.files.createFile(atPath: path.string, contents: resumeData)
        }
    }
}

extension URLSession {
    public func downloadTask(_: PMKNamespacer, with convertible: URLRequestConvertible, to saveLocation: URL, resumingWith resumeData: Data?) -> (progress: Progress, promise: Promise<(saveLocation: URL, response: URLResponse)>) {
        var progress: Progress!

        let promise = Promise<(saveLocation: URL, response: URLResponse)> { seal in
            let completionHandler = { (temporaryURL: URL?, response: URLResponse?, error: Error?) in
                if let error = error {
                    seal.reject(error)
                } else if let response = response, let temporaryURL = temporaryURL {
                    do {
                        try FileManager.default.moveItem(at: temporaryURL, to: saveLocation)
                        seal.fulfill((saveLocation, response))
                    } catch {
                        seal.reject(error)
                    }
                } else {
                    seal.reject(PMKError.invalidCallingConvention)
                }
            }
            
            let task: URLSessionDownloadTask
            if let resumeData = resumeData {
                task = downloadTask(withResumeData: resumeData, completionHandler: completionHandler)
            }
            else {
                task = downloadTask(with: convertible.pmkRequest, completionHandler: completionHandler)
            }
            progress = task.progress
            task.resume()
        }

        return (progress, promise)
    }
}

/// Attempt and retry a task that fails with resume data up to `maximumRetryCount` times
private func attemptResumableTask<T>(maximumRetryCount: Int = 3, delayBeforeRetry: DispatchTimeInterval = .seconds(2), _ body: @escaping (Data?) -> Promise<T>) -> Promise<T> {
    var attempts = 0
    func attempt(with resumeData: Data? = nil) -> Promise<T> {
        attempts += 1
        return body(resumeData).recover { error -> Promise<T> in
            guard
                attempts < maximumRetryCount,
                let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            else { throw error }

            return after(delayBeforeRetry).then(on: nil) { attempt(with: resumeData) }
        }
    }
    return attempt()
}
