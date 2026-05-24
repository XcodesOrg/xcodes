import Foundation
@preconcurrency import Path
import XcodesKit

public enum Downloader: Sendable {
    case urlSession
    case aria2(Path)

    public init(aria2Path: String?) {
        guard let aria2Path = aria2Path.flatMap(Path.init) ?? Current.shell.findExecutable("aria2c"), aria2Path.exists else {
            self = .urlSession
            return
        }
        self = .aria2(aria2Path)
    }

    func download(url: URL, to destination: Path, progressChanged: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        switch self {
            case .urlSession:
                if Current.shell.isatty() {
                    Current.logging.log("Downloading with urlSession - for faster downloads install aria2 (`brew install aria2`)".black.onYellow)
                    // Add 1 extra line as we are overwriting with download progress
                    Current.logging.log("")
                }
                return try await withUrlSession(url: url, to: destination, progressChanged: progressChanged)
            case .aria2(let aria2Path):
                if Current.shell.isatty() {
                    Current.logging.log("Downloading with aria2 (\(aria2Path))".green)
                    // Add 1 extra line as we are overwriting with download progress
                    Current.logging.log("")
                }
                return try await withAria(aria2Path: aria2Path, url: url, to: destination, progressChanged: progressChanged)
        }
    }

    var aria2Path: Path? {
        if case let .aria2(path) = self {
            return path
        }
        return nil
    }

    private func withAria(aria2Path: Path, url: URL, to destination: Path, progressChanged: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        try await archiveDownloadStrategyService(aria2Path: aria2Path).download(
            url: url,
            destination: destination,
            downloader: .aria2,
            resumeDataPath: resumeDataPath(for: destination),
            progressChanged: progressChanged
        )
    }

    private func withUrlSession(url: URL, to destination: Path, progressChanged: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        try await archiveDownloadStrategyService().download(
            url: url,
            destination: destination,
            downloader: .urlSession,
            resumeDataPath: resumeDataPath(for: destination),
            progressChanged: progressChanged
        )
    }

    private func resumeDataPath(for destination: Path) -> Path {
        destination.parent/(destination.basename() + ".resumedata")
    }

    private static func shouldRetryDownloadError(_ error: Error) -> Bool {
        if case XcodeInstaller.Error.unauthorized = error {
            return false
        }

        return true
    }

    private var archiveDownloadService: ArchiveDownloadService {
        ArchiveDownloadService(
            aria2Download: Current.shell.downloadWithAria2,
            urlSessionDownload: { url, destination, resumeData in
                Current.network.downloadTask(
                    with: URLRequest(url: url),
                    to: destination,
                    resumingWith: resumeData
                )
            },
            contentsAtPath: { path in Current.files.contents(atPath: path) },
            createFile: { path, data in
                Current.files.createFile(atPath: path, contents: data)
            },
            removeItem: { try Current.files.removeItem(at: $0) },
            shouldRetry: { Self.shouldRetryDownloadError($0) },
            validateResponse: { response in
                try ArchiveDownloadService.validateDeveloperDownloadResponse(
                    response,
                    unauthorizedError: { XcodeInstaller.Error.unauthorized }
                )
            }
        )
    }

    private func archiveDownloadStrategyService(aria2Path: Path? = nil) -> ArchiveDownloadStrategyService {
        ArchiveDownloadStrategyService(
            archiveDownloadService: archiveDownloadService,
            aria2Path: {
                guard let aria2Path else {
                    throw XcodesKitError("aria2 path is unavailable.")
                }
                return aria2Path
            },
            cookiesForURL: { Current.network.session.configuration.httpCookieStorage?.cookies(for: $0) ?? [] }
        )
    }
}

extension XcodeArchiveDownloader {
    init(_ downloader: Downloader) {
        switch downloader {
        case .aria2:
            self = .aria2
        case .urlSession:
            self = .urlSession
        }
    }
}
