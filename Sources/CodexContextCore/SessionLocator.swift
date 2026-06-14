import Foundation

public struct SessionLocator {
    public let codexHome: URL
    public let fileManager: FileManager

    public init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        fileManager: FileManager = .default
    ) {
        self.codexHome = codexHome
        self.fileManager = fileManager
    }

    public func latestUserSession() throws -> SessionChoice {
        guard let selected = try recentUserSessions(limit: 1).first else {
            throw ContextMonitorError.noSessionsFound(codexHome.appendingPathComponent("sessions"))
        }
        return selected
    }

    public func session(id: String) throws -> SessionChoice {
        let sessionsRoot = codexHome.appendingPathComponent("sessions")
        guard fileManager.fileExists(atPath: sessionsRoot.path) else {
            throw ContextMonitorError.codexDirectoryMissing(sessionsRoot)
        }

        let index = SessionIndex.load(codexHome: codexHome)
        let files = sessionFiles(root: sessionsRoot)
        for file in filesLikelyMatching(id: id, in: files) + files {
            guard let located = metadata(for: file, index: index),
                  located.choice.id == id,
                  located.threadSource == "user" else {
                continue
            }
            return located.choice
        }

        throw ContextMonitorError.noSessionsFound(sessionsRoot)
    }

    public func recentUserSessions(limit: Int = 20) throws -> [SessionChoice] {
        let sessionsRoot = codexHome.appendingPathComponent("sessions")
        guard fileManager.fileExists(atPath: sessionsRoot.path) else {
            throw ContextMonitorError.codexDirectoryMissing(sessionsRoot)
        }

        let index = SessionIndex.load(codexHome: codexHome)
        let files = sessionFiles(root: sessionsRoot)
        let indexedCandidates = recentIndexEntries(index: index, limit: metadataScanLimit(limit: limit, fileCount: files.count))
            .compactMap { entry in
                filesLikelyMatching(id: entry.id, in: files).first
            }

        let fallbackCandidates = filesByModificationDate(files, limit: metadataScanLimit(limit: limit, fileCount: files.count))
        var candidates = uniqueFiles(indexedCandidates + fallbackCandidates)
            .compactMap { metadata(for: $0, index: index) }
            .filter { $0.threadSource == "user" }
            .sorted { $0.updatedAt > $1.updatedAt }

        if candidates.isEmpty {
            candidates = files
                .compactMap { metadata(for: $0, index: index) }
                .filter { $0.threadSource == "user" }
                .sorted { $0.updatedAt > $1.updatedAt }
        }

        guard !candidates.isEmpty else {
            throw ContextMonitorError.noSessionsFound(sessionsRoot)
        }

        return candidates.prefix(max(1, limit)).map(\.choice)
    }

    private func sessionFiles(root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else {
                return nil
            }
            return url
        }
    }

    private func filesLikelyMatching(id: String, in files: [URL]) -> [URL] {
        files.filter { $0.deletingPathExtension().lastPathComponent.contains(id) }
    }

    private func filesByModificationDate(_ files: [URL], limit: Int) -> [URL] {
        files
            .map { file in
                SessionFileCandidate(url: file, modifiedAt: modificationDate(for: file) ?? .distantPast)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map(\.url)
    }

    private func metadataScanLimit(limit: Int, fileCount: Int) -> Int {
        guard limit > 0 else {
            return min(fileCount, 1)
        }
        guard limit < fileCount, limit < Int.max / 4 else {
            return fileCount
        }
        return min(fileCount, max(50, limit * 4))
    }

    private func recentIndexEntries(index: [String: SessionIndexEntry], limit: Int) -> [SessionIndexEntry] {
        index.values
            .sorted {
                ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }

    private func uniqueFiles(_ files: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for file in files {
            guard seen.insert(file.path).inserted else {
                continue
            }
            result.append(file)
        }
        return result
    }

    private func metadata(for file: URL, index: [String: SessionIndexEntry]) -> LocatedSession? {
        guard let meta = SessionFileReader.readSessionMeta(from: file) else {
            return nil
        }

        let id = meta.id
        let updatedAt = [index[id]?.updatedAt, modificationDate(for: file), meta.timestamp]
            .compactMap { $0 }
            .max() ?? .distantPast
        let choice = SessionChoice(
            id: id,
            name: index[id]?.threadName,
            path: file,
            cwd: meta.cwd,
            updatedAt: updatedAt
        )

        return LocatedSession(choice: choice, threadSource: meta.threadSource, updatedAt: updatedAt)
    }

    private func modificationDate(for file: URL) -> Date? {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

private struct SessionFileCandidate {
    let url: URL
    let modifiedAt: Date
}

private struct LocatedSession {
    let choice: SessionChoice
    let threadSource: String
    let updatedAt: Date
}

struct SessionMeta {
    let id: String
    let timestamp: Date?
    let cwd: String?
    let threadSource: String
    let baseInstructions: String
    let dynamicTools: [DynamicTool]
}

struct DynamicTool: Equatable {
    let namespace: String
    let name: String
    let description: String

    var displayName: String {
        namespace.isEmpty ? name : "\(namespace).\(name)"
    }
}
