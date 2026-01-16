import Foundation
import Path
import Version
import PromiseKit
import SwiftSoup
import struct XCModel.Xcode

/// Provides lists of available and installed Xcodes
public final class XcodeList {
    public init() {
        try? loadCachedAvailableXcodes()
    }

    public private(set) var availableXcodes: [Xcode] = []
    public private(set) var lastUpdated: Date?

    public var shouldUpdateBeforeListingVersions: Bool {
        return availableXcodes.isEmpty || (cacheAge ?? 0) > Self.maxCacheAge
    }

    public func shouldUpdateBeforeDownloading(version: Version) -> Bool {
        return availableXcodes.first(withVersion: version) == nil
    }

    public func update(dataSource: DataSource) -> Promise<[Xcode]> {
        let xcodesPromise: Promise<[Xcode]>

        switch dataSource {
        case .apple:
            xcodesPromise = when(fulfilled: releasedXcodes(), prereleaseXcodes())
                .map { releasedXcodes, prereleaseXcodes in
                    // Starting with Xcode 11 beta 6, developer.apple.com/download and developer.apple.com/download/more both list some pre-release versions of Xcode.
                    // Previously pre-release versions only appeared on developer.apple.com/download.
                    // /download/more doesn't include build numbers, so we trust that if the version number and prerelease identifiers are the same that they're the same build.
                    // If an Xcode version is listed on both sites then prefer the one on /download because the build metadata is used to compare against installed Xcodes.
                    let xcodes = releasedXcodes.filter { releasedXcode in
                        prereleaseXcodes.contains { $0.version.isEquivalent(to: releasedXcode.version) } == false
                    } + prereleaseXcodes
                    return xcodes
                }
        case .xcodeReleases:
            xcodesPromise = xcodeReleases()
        }

        return xcodesPromise.map { xcodes in
            // Apply architecture filtering centrally for all data sources
            let filtered = self.filterArchitectureVariants(xcodes)
            self.availableXcodes = filtered
            self.lastUpdated = Date()
            try? self.cacheAvailableXcodes(filtered)
            return filtered
        }
    }
}

extension XcodeList {
    private static let maxCacheAge = TimeInterval(86400) // 24 hours

    private var cacheAge: TimeInterval? {
        guard let lastUpdated = lastUpdated else { return nil }
        return -lastUpdated.timeIntervalSinceNow
    }

    private func loadCachedAvailableXcodes() throws {
        guard let data = Current.files.contents(atPath: Path.cacheFile.string) else { return }
        let xcodes = try JSONDecoder().decode([Xcode].self, from: data)

        let attributes = try? Current.files.attributesOfItem(atPath: Path.cacheFile.string)
        let lastUpdated = attributes?[.modificationDate] as? Date

        self.availableXcodes = xcodes
        self.lastUpdated = lastUpdated
    }

    private func cacheAvailableXcodes(_ xcodes: [Xcode]) throws {
        let data = try JSONEncoder().encode(xcodes)
        try FileManager.default.createDirectory(at: Path.cacheFile.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Current.files.write(data, to: Path.cacheFile.url)
    }
}

extension XcodeList {
    // MARK: - Apple

    private func releasedXcodes() -> Promise<[Xcode]> {
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            Current.network.dataTask(with: URLRequest.downloads)
        }
        .map { (data, response) -> [Xcode] in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(.downloadsDateModified)
            let downloads = try decoder.decode(Downloads.self, from: data)
            let xcodes = downloads
                .downloads
                .filter { $0.name.range(of: "^Xcode [0-9]", options: .regularExpression) != nil }
                .compactMap { download -> Xcode? in
                    let urlPrefix = URL(string: "https://download.developer.apple.com/")!
                    guard 
                        let xcodeFile = download.files.first(where: { $0.remotePath.hasSuffix("dmg") || $0.remotePath.hasSuffix("xip") }),
                        let version = Version(xcodeVersion: download.name)
                    else { return nil }

                    let url = urlPrefix.appendingPathComponent(xcodeFile.remotePath)
                    return Xcode(version: version, url: url, filename: String(xcodeFile.remotePath.suffix(fromLast: "/")), releaseDate: download.dateModified)
                }
            return xcodes
        }
    }

    private func prereleaseXcodes() -> Promise<[Xcode]> {
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            Current.network.dataTask(with: URLRequest.download)
        }
        .map { (data, _) -> [Xcode] in
            try self.parsePrereleaseXcodes(from: data)
        }
    }

    func parsePrereleaseXcodes(from data: Data) throws -> [Xcode] {
        let body = String(data: data, encoding: .utf8)!
        let document = try SwiftSoup.parse(body)

        guard 
            let xcodeHeader = try document.select("h2:containsOwn(Xcode)").first(),
            let productBuildVersion = try xcodeHeader.parent()?.select("li:contains(Build)").text().replacingOccurrences(of: "Build", with: ""),
            let releaseDateString = try xcodeHeader.parent()?.select("li:contains(Released)").text().replacingOccurrences(of: "Released", with: ""),
            let version = Version(xcodeVersion: try xcodeHeader.text(), buildMetadataIdentifier: productBuildVersion),
            let path = try document.select(".direct-download[href*=xip]").first()?.attr("href"),
            let url = URL(string: "https://developer.apple.com" + path)
        else { return [] }

        let filename = String(path.suffix(fromLast: "/"))

        return [Xcode(version: version, url: url, filename: filename, releaseDate: DateFormatter.downloadsReleaseDate.date(from: releaseDateString))]
    }
}

extension XcodeList {
    // MARK: - XcodeReleases
    
    private func xcodeReleases() -> Promise<[Xcode]> {
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            Current.network.dataTask(with: URLRequest(url: URL(string: "https://xcodereleases.com/data.json")!))
        }
        .map { (data, response) in
            let decoder = JSONDecoder()
            let xcReleasesXcodes = try decoder.decode([XCModel.Xcode].self, from: data)
            let xcodes = xcReleasesXcodes.compactMap { xcReleasesXcode -> Xcode? in
                guard
                    let downloadURL = xcReleasesXcode.links?.download?.url,
                    let version = Version(xcReleasesXcode: xcReleasesXcode)
                else { return nil }
                
                let releaseDate = Calendar(identifier: .gregorian).date(from: DateComponents(
                    year: xcReleasesXcode.date.year,
                    month: xcReleasesXcode.date.month,
                    day: xcReleasesXcode.date.day
                ))
                
                return Xcode(
                    version: version,
                    url: downloadURL,
                    filename: String(downloadURL.path.suffix(fromLast: "/")),
                    releaseDate: releaseDate
                )
            }
            return xcodes
        }
        .map(filterPrereleasesThatMatchReleaseBuildMetadataIdentifiers)
    }
    
    /// Xcode Releases may have multiple releases with the same build metadata when a build doesn't change between candidate and final releases.
    /// For example, 12.3 RC and 12.3 are both build 12C33
    /// We don't care about that difference, so only keep the final release (GM or Release, in XCModel terms).
    /// The downside of this is that a user could technically have both releases installed, and so they won't both be shown in the list, but I think most users wouldn't do this.
    func filterPrereleasesThatMatchReleaseBuildMetadataIdentifiers(_ xcodes: [Xcode]) -> [Xcode] {
        var filteredXcodes: [Xcode] = []
        for xcode in xcodes {
            if xcode.version.buildMetadataIdentifiers.isEmpty {
                filteredXcodes.append(xcode)
                continue
            }
            
            let xcodesWithSameBuildMetadataIdentifiers = xcodes
                .filter({ $0.version.buildMetadataIdentifiers == xcode.version.buildMetadataIdentifiers })
            if xcodesWithSameBuildMetadataIdentifiers.count > 1,
               xcode.version.prereleaseIdentifiers.isEmpty || xcode.version.prereleaseIdentifiers == ["GM"] {
                filteredXcodes.append(xcode)
            } else if xcodesWithSameBuildMetadataIdentifiers.count == 1 {
                filteredXcodes.append(xcode)
            }
        }
        return filteredXcodes
    }

    /// Filters architecture variants to select the appropriate one for the current machine.
    /// When multiple architecture variants exist for the same version (e.g., Apple_silicon and Universal),
    /// selects the one that matches the current machine's architecture.
    private func filterArchitectureVariants(_ xcodes: [Xcode]) -> [Xcode] {
        let machine = Current.shell.machineArchitecture()
        let isAppleSilicon = machine == "arm64"

        // Group by version to find duplicates
        var versionGroups: [Version: [Xcode]] = [:]
        for xcode in xcodes {
            versionGroups[xcode.version, default: []].append(xcode)
        }

        var filtered: [Xcode] = []
        for (_, variants) in versionGroups {
            if variants.count == 1 {
                // No architecture variants, keep as-is
                filtered.append(variants[0])
            } else {
                // Multiple variants - select based on architecture
                let selected: Xcode
                if isAppleSilicon {
                    // Prefer Apple_silicon, fallback to Universal
                    selected = variants.first { $0.url.absoluteString.contains("Apple_silicon") }
                            ?? variants.first { $0.url.absoluteString.contains("Universal") }
                            ?? variants[0]
                } else {
                    // On Intel, prefer Universal, avoid Apple_silicon
                    selected = variants.first { $0.url.absoluteString.contains("Universal") }
                            ?? variants.first { !$0.url.absoluteString.contains("Apple_silicon") }
                            ?? variants[0]
                }

                filtered.append(selected)
            }
        }

        return filtered
    }
}
