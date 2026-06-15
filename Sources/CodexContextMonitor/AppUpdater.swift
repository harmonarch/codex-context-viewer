import Foundation

struct AppVersion {
    static let fallback = "0.1.5"

    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallback
    }
}

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
    case latestTagNotFound
    case noDMGAsset
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The update server returned an unreadable response."
        case .latestTagNotFound:
            "The latest version could not be found."
        case .noDMGAsset:
            "The latest release does not include a DMG installer."
        case .downloadFailed:
            "The installer could not be downloaded."
        }
    }
}

struct AppUpdater {
    private static let owner = "harmonarch"
    private static let repository = "codex-context-viewer"
    private static let assetName = "Codex-Context-Monitor.dmg"
    private let latestReleaseURL = URL(string: "https://github.com/\(Self.owner)/\(Self.repository)/releases/latest")!
    private let fileManager: FileManager
    private let session: URLSession

    init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    func latestUpdate(currentVersion: String) async throws -> AppUpdate? {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("CodexContextMonitor", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateError.invalidResponse
        }

        guard let tagName = Self.releaseTag(from: httpResponse.url) else {
            throw AppUpdateError.latestTagNotFound
        }

        let version = Self.normalizedVersion(tagName)
        guard Self.compareVersions(version, currentVersion) == .orderedDescending else {
            return nil
        }

        let releaseURL = Self.releaseURL(tagName: tagName)
        let assetDownloadURL = Self.assetDownloadURL(tagName: tagName)

        return AppUpdate(
            version: version,
            tagName: tagName,
            releaseURL: releaseURL,
            assetName: Self.assetName,
            assetDownloadURL: assetDownloadURL
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

    static func releaseTag(from url: URL?) -> String? {
        guard let url else {
            return nil
        }

        let pathParts = url.path.split(separator: "/").map(String.init)
        guard let tagIndex = pathParts.firstIndex(of: "tag"),
              tagIndex + 1 < pathParts.count else {
            return nil
        }

        return pathParts[tagIndex + 1]
    }

    static func releaseURL(tagName: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases/tag/\(tagName)")!
    }

    static func assetDownloadURL(tagName: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases/download/\(tagName)/\(assetName)")!
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
