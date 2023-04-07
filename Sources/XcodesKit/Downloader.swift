import PromiseKit
import Foundation
import Path
import AppleAPI

public enum Downloader {
    case urlSession
    case aria2(Path)

    public init(aria2Path: String?) {
        guard let aria2Path = aria2Path.flatMap(Path.init) ?? Current.shell.findExecutable("aria2c"), aria2Path.exists else {
            self = .urlSession
            return
        }
        self = .aria2(aria2Path)
    }

    func download(url: URL, to destination: Path, progressChanged: @escaping (Progress) -> Void) -> Promise<URL> {
        switch self {
            case .urlSession:
                if Current.shell.isatty() {
                    Current.logging.log("Downloading with urlSession - for faster downloads install aria2 (`brew install aria2`)".black.onYellow)
                    // Add 1 extra line as we are overwriting with download progress
                    Current.logging.log("")
                }
                return withUrlSession(url: url, to: destination, progressChanged: progressChanged)
            case .aria2(let aria2Path):
                if Current.shell.isatty() {
                    Current.logging.log("Downloading with aria2 (\(aria2Path))".green)
                    // Add 1 extra line as we are overwriting with download progress
                    Current.logging.log("")
                }
                return withAria(aria2Path: aria2Path, url: url, to: destination, progressChanged: progressChanged)
        }
    }

    private func withAria(aria2Path: Path, url: URL, to destination: Path, progressChanged: @escaping (Progress) -> Void) -> Promise<URL> {
        let cookies = AppleAPI.Current.network.session.configuration.httpCookieStorage?.cookies(for: url) ?? []
        return attemptRetryableTask(maximumRetryCount: 3) {
            let (progress, promise) = Current.shell.downloadWithAria2(
                aria2Path,
                url,
                destination,
                cookies
            )
            progressChanged(progress)
            return promise.map { _ in destination.url }
        }
    }

    private func withUrlSession(url: URL, to destination: Path, progressChanged: @escaping (Progress) -> Void) -> Promise<URL> {
        let resumeDataPath = destination.parent/(destination.basename() + ".resumedata")
        let persistedResumeData = Current.files.contents(atPath: resumeDataPath.string)

        return attemptResumableTask(maximumRetryCount: 3) { resumeData in
            let (progress, promise) = Current.network.downloadTask(with: url,
                                                                   to: destination.url,
                                                                   resumingWith: resumeData ?? persistedResumeData)
            progressChanged(progress)
            return promise.map { result in
                /// If the operation is unauthorized, the download page redirects to https://developer.apple.com/unauthorized/
                /// with 200 status. After that the html page is downloaded as a xip and subsequent unxipping fails
                guard result.response.url?.lastPathComponent != "unauthorized" else {
                    throw XcodeInstaller.Error.unauthorized
                }
                
                return result.saveLocation
            }
        }
        .tap { result in
            self.persistOrCleanUpResumeData(at: resumeDataPath, for: result)
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
