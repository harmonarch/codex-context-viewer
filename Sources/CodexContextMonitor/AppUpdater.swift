import Foundation

struct AppUpdate: Equatable, Sendable {
    let version: String
    let tagName: String
    let releaseURL: URL
    let assetName: String
    let assetDownloadURL: URL
}

enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate(Date)
    case available(AppUpdate)
    case downloading(AppUpdate)
    case downloaded(AppUpdate, URL)
    case failed(String)
}

enum AppUpdateError: LocalizedError {
    case invalidResponse
    case noDMGAsset
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The update server returned an unreadable response."
        case .noDMGAsset:
            "The latest release does not include a DMG installer."
        case .downloadFailed:
            "The installer could not be downloaded."
        }
    }
}

struct AppUpdater {
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/harmonarch/codex-context-viewer/releases/latest")!
    private let fileManager: FileManager
    private let session: URLSession

    init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    func latestUpdate(currentVersion: String) async throws -> AppUpdate? {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodexContextMonitor", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateError.invalidResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = Self.normalizedVersion(release.tagName)
        guard Self.compareVersions(version, currentVersion) == .orderedDescending else {
            return nil
        }

        guard let asset = release.assets.first(where: { $0.name.localizedCaseInsensitiveContains("Codex-Context-Monitor") && $0.name.lowercased().hasSuffix(".dmg") })
                ?? release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
            throw AppUpdateError.noDMGAsset
        }

        return AppUpdate(
            version: version,
            tagName: release.tagName,
            releaseURL: release.htmlURL,
            assetName: asset.name,
            assetDownloadURL: asset.browserDownloadURL
        )
    }

    func download(_ update: AppUpdate) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: update.assetDownloadURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateError.downloadFailed
        }

        let destination = downloadsDirectory()
            .appendingPathComponent(Self.installerFileName(for: update), isDirectory: false)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func downloadsDirectory() -> URL {
        fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
    }

    static func installerFileName(for update: AppUpdate) -> String {
        let extensionName = URL(fileURLWithPath: update.assetName).pathExtension
        let baseName = update.assetName.dropLast(extensionName.isEmpty ? 0 : extensionName.count + 1)
        return "\(baseName)-\(update.tagName).\(extensionName.isEmpty ? "dmg" : extensionName)"
    }

    static func normalizedVersion(_ value: String) -> String {
        var version = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.lowercased().hasPrefix("version") {
            version = String(version.dropFirst("version".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if version.lowercased().hasPrefix("v") {
            version = String(version.dropFirst())
        }
        return version
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = normalizedVersion(lhs).split(separator: ".").map(versionPart)
        let rhsParts = normalizedVersion(rhs).split(separator: ".").map(versionPart)
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func versionPart(_ value: Substring) -> Int {
        Int(value.prefix { $0.isNumber }) ?? 0
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
