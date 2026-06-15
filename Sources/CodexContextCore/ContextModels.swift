import Foundation

public struct SessionChoice: Equatable, Sendable {
    public let id: String
    public let name: String?
    public let path: URL
    public let cwd: String?
    public let updatedAt: Date

    public init(id: String, name: String?, path: URL, cwd: String?, updatedAt: Date) {
        self.id = id
        self.name = name
        self.path = path
        self.cwd = cwd
        self.updatedAt = updatedAt
    }
}

public struct ContextSnapshot: Equatable, Sendable {
    public let session: SessionChoice?
    public let generatedAt: Date
    public let contextWindow: Int
    public let lastInputTokens: Int
    public let cachedInputTokens: Int
    public let totalRunTokens: Int
    public let categories: [ContextCategory]
    public let warnings: [String]
    public let baseline: ContextBaseline?

    public init(
        session: SessionChoice?,
        generatedAt: Date,
        contextWindow: Int,
        lastInputTokens: Int,
        cachedInputTokens: Int,
        totalRunTokens: Int,
        categories: [ContextCategory],
        warnings: [String] = [],
        baseline: ContextBaseline? = nil
    ) {
        self.session = session
        self.generatedAt = generatedAt
        self.contextWindow = contextWindow
        self.lastInputTokens = lastInputTokens
        self.cachedInputTokens = cachedInputTokens
        self.totalRunTokens = totalRunTokens
        self.categories = categories
        self.warnings = warnings
        self.baseline = baseline
    }

    public var usageRatio: Double {
        ratio(for: lastInputTokens)
    }

    public var displayUsageRatio: Double {
        ratio(for: displayInputTokens)
    }

    private func ratio(for tokens: Int) -> Double {
        guard contextWindow > 0 else { return 0 }
        return min(1, Double(tokens) / Double(contextWindow))
    }

    public var estimatedCategoryTokens: Int {
        categories.reduce(0) { $0 + $1.tokens }
    }

    public var displayInputTokens: Int {
        guard let baseline else { return lastInputTokens }
        return max(0, lastInputTokens - baseline.lastInputTokens)
    }

    public var displayCachedInputTokens: Int {
        guard let baseline else { return cachedInputTokens }
        return max(0, cachedInputTokens - baseline.cachedInputTokens)
    }

    public var displayTotalRunTokens: Int {
        guard let baseline else { return totalRunTokens }
        return max(0, totalRunTokens - baseline.totalRunTokens)
    }
}

public struct ContextBaseline: Equatable, Sendable, Codable {
    public let sessionID: String
    public let lineCount: Int
    public let lastInputTokens: Int
    public let cachedInputTokens: Int
    public let totalRunTokens: Int
    public let baselineSetAt: Date

    public init(
        sessionID: String,
        lineCount: Int,
        lastInputTokens: Int,
        cachedInputTokens: Int,
        totalRunTokens: Int,
        baselineSetAt: Date
    ) {
        self.sessionID = sessionID
        self.lineCount = lineCount
        self.lastInputTokens = lastInputTokens
        self.cachedInputTokens = cachedInputTokens
        self.totalRunTokens = totalRunTokens
        self.baselineSetAt = baselineSetAt
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case lineCount
        case lastInputTokens
        case cachedInputTokens
        case totalRunTokens
        case baselineSetAt
        case clearedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        lineCount = try container.decode(Int.self, forKey: .lineCount)
        lastInputTokens = try container.decode(Int.self, forKey: .lastInputTokens)
        cachedInputTokens = try container.decode(Int.self, forKey: .cachedInputTokens)
        totalRunTokens = try container.decode(Int.self, forKey: .totalRunTokens)
        baselineSetAt = try container.decodeIfPresent(Date.self, forKey: .baselineSetAt)
            ?? container.decode(Date.self, forKey: .clearedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(lineCount, forKey: .lineCount)
        try container.encode(lastInputTokens, forKey: .lastInputTokens)
        try container.encode(cachedInputTokens, forKey: .cachedInputTokens)
        try container.encode(totalRunTokens, forKey: .totalRunTokens)
        try container.encode(baselineSetAt, forKey: .baselineSetAt)
    }
}

public struct ContextCategory: Equatable, Sendable {
    public let kind: ContextCategoryKind
    public let tokens: Int
    public let items: [ContextItem]

    public init(kind: ContextCategoryKind, tokens: Int, items: [ContextItem]) {
        self.kind = kind
        self.tokens = tokens
        self.items = items
    }
}

public enum ContextCategoryKind: String, CaseIterable, Sendable {
    case instructions = "Instructions"
    case skills = "Skills"
    case mcp = "MCP"
    case files = "Files"
    case messages = "Messages"
    case toolCalls = "Tool Calls"
    case toolOutput = "Tool Output"
    case reasoning = "Reasoning"
    case other = "Other"

    public var sortOrder: Int {
        switch self {
        case .instructions: 0
        case .skills: 1
        case .mcp: 2
        case .files: 3
        case .messages: 4
        case .toolCalls: 5
        case .toolOutput: 6
        case .reasoning: 7
        case .other: 8
        }
    }
}

public struct ContextItem: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let tokens: Int
    public let count: Int

    public init(title: String, subtitle: String? = nil, tokens: Int, count: Int = 1) {
        self.title = title
        self.subtitle = subtitle
        self.tokens = tokens
        self.count = count
    }
}

public enum ContextMonitorError: Error, LocalizedError {
    case codexDirectoryMissing(URL)
    case noSessionsFound(URL)
    case unreadableSession(URL)

    public var errorDescription: String? {
        switch self {
        case .codexDirectoryMissing(let url):
            "Codex folder was not found at \(url.path)."
        case .noSessionsFound(let url):
            "No Codex session files were found under \(url.path)."
        case .unreadableSession(let url):
            "The selected Codex session could not be read: \(url.path)."
        }
    }
}
