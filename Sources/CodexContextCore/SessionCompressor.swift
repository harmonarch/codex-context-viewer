import Foundation

public struct SessionCompressionOptions: Equatable, Sendable {
    public let maxLatestUserMessages: Int
    public let maxRecentMessages: Int
    public let maxReferencedFiles: Int
    public let maxToolActivities: Int
    public let maxTextCharacters: Int

    public init(
        maxLatestUserMessages: Int = 3,
        maxRecentMessages: Int = 14,
        maxReferencedFiles: Int = 24,
        maxToolActivities: Int = 12,
        maxTextCharacters: Int = 900
    ) {
        self.maxLatestUserMessages = max(1, maxLatestUserMessages)
        self.maxRecentMessages = max(1, maxRecentMessages)
        self.maxReferencedFiles = max(1, maxReferencedFiles)
        self.maxToolActivities = max(1, maxToolActivities)
        self.maxTextCharacters = max(80, maxTextCharacters)
    }
}

public struct SessionCompressionDraft: Equatable, Sendable {
    public let session: SessionChoice
    public let generatedAt: Date
    public let sourceLineCount: Int
    public let sourceTokenEstimate: Int
    public let lastInputTokens: Int
    public let cachedInputTokens: Int
    public let totalRunTokens: Int
    public let contextWindow: Int
    public let latestUserMessages: [CompressedMessage]
    public let recentMessages: [CompressedMessage]
    public let referencedFiles: [String]
    public let recentToolActivities: [CompressedToolActivity]
    public let omittedMessageCount: Int
    public let omittedToolActivityCount: Int

    public init(
        session: SessionChoice,
        generatedAt: Date,
        sourceLineCount: Int,
        sourceTokenEstimate: Int,
        lastInputTokens: Int,
        cachedInputTokens: Int,
        totalRunTokens: Int,
        contextWindow: Int,
        latestUserMessages: [CompressedMessage],
        recentMessages: [CompressedMessage],
        referencedFiles: [String],
        recentToolActivities: [CompressedToolActivity],
        omittedMessageCount: Int,
        omittedToolActivityCount: Int
    ) {
        self.session = session
        self.generatedAt = generatedAt
        self.sourceLineCount = sourceLineCount
        self.sourceTokenEstimate = sourceTokenEstimate
        self.lastInputTokens = lastInputTokens
        self.cachedInputTokens = cachedInputTokens
        self.totalRunTokens = totalRunTokens
        self.contextWindow = contextWindow
        self.latestUserMessages = latestUserMessages
        self.recentMessages = recentMessages
        self.referencedFiles = referencedFiles
        self.recentToolActivities = recentToolActivities
        self.omittedMessageCount = omittedMessageCount
        self.omittedToolActivityCount = omittedToolActivityCount
    }
}

public struct CompressedMessage: Equatable, Sendable {
    public let role: String
    public let text: String

    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

public struct CompressedToolActivity: Equatable, Sendable {
    public let title: String
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

public struct SessionCompressor {
    public let options: SessionCompressionOptions

    public init(options: SessionCompressionOptions = SessionCompressionOptions()) {
        self.options = options
    }

    public func compress(session: SessionChoice) throws -> SessionCompressionDraft {
        guard let text = try? String(contentsOf: session.path, encoding: .utf8) else {
            throw ContextMonitorError.unreadableSession(session.path)
        }

        var messages: [CompressedMessage] = []
        var toolActivities: [CompressedToolActivity] = []
        var referencedFiles = OrderedStrings()
        var visibleTokenEstimate = 0
        var contextWindow = 0
        var lastInputTokens = 0
        var cachedInputTokens = 0
        var totalRunTokens = 0
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines {
            guard let event = JSONValue.parse(line: String(line)),
                  let type = event["type"]?.string else {
                continue
            }

            switch type {
            case "response_item":
                guard let payload = event["payload"],
                      let itemType = payload["type"]?.string else {
                    continue
                }
                consumeResponseItem(
                    payload,
                    itemType: itemType,
                    messages: &messages,
                    toolActivities: &toolActivities,
                    referencedFiles: &referencedFiles,
                    visibleTokenEstimate: &visibleTokenEstimate
                )
            case "event_msg":
                guard let payload = event["payload"] else {
                    continue
                }
                if payload["type"]?.string == "token_count",
                   let info = payload["info"] {
                    contextWindow = info["model_context_window"]?.int ?? contextWindow
                    lastInputTokens = info["last_token_usage"]?["input_tokens"]?.int ?? lastInputTokens
                    cachedInputTokens = info["last_token_usage"]?["cached_input_tokens"]?.int ?? cachedInputTokens
                    totalRunTokens = info["total_token_usage"]?["total_tokens"]?.int ?? totalRunTokens
                } else if payload["type"]?.string == "mcp_tool_call_end" {
                    let activity = mcpActivity(from: payload)
                    toolActivities.append(activity)
                    referencedFiles.insert(contentsOf: fileReferences(in: activity.detail))
                    visibleTokenEstimate += TokenEstimator.estimate(activity.detail)
                }
            default:
                continue
            }
        }

        let recentMessages = messages.suffix(options.maxRecentMessages)
        let recentTools = toolActivities.suffix(options.maxToolActivities)
        let latestUserMessages = messages
            .filter { $0.role == "user" }
            .suffix(options.maxLatestUserMessages)

        return SessionCompressionDraft(
            session: session,
            generatedAt: Date(),
            sourceLineCount: lines.count,
            sourceTokenEstimate: max(lastInputTokens, visibleTokenEstimate),
            lastInputTokens: lastInputTokens,
            cachedInputTokens: cachedInputTokens,
            totalRunTokens: totalRunTokens,
            contextWindow: contextWindow,
            latestUserMessages: Array(latestUserMessages),
            recentMessages: Array(recentMessages),
            referencedFiles: Array(referencedFiles.values.prefix(options.maxReferencedFiles)),
            recentToolActivities: Array(recentTools),
            omittedMessageCount: max(0, messages.count - recentMessages.count),
            omittedToolActivityCount: max(0, toolActivities.count - recentTools.count)
        )
    }

    private func consumeResponseItem(
        _ payload: JSONValue,
        itemType: String,
        messages: inout [CompressedMessage],
        toolActivities: inout [CompressedToolActivity],
        referencedFiles: inout OrderedStrings,
        visibleTokenEstimate: inout Int
    ) {
        switch itemType {
        case "message":
            let role = payload["role"]?.string ?? "message"
            guard role == "user" || role == "assistant" else {
                return
            }
            let content = trimmed(messageContent(payload))
            guard !content.isEmpty else {
                return
            }
            messages.append(CompressedMessage(role: role, text: content))
            referencedFiles.insert(contentsOf: fileReferences(in: content))
            visibleTokenEstimate += TokenEstimator.estimate(content)
        case "function_call", "tool_search_call":
            let namespace = payload["namespace"]?.string
            let name = payload["name"]?.string ?? itemType
            let displayName = [namespace, name].compactMap { $0 }.joined(separator: ".")
            let detail = trimmed(payload["arguments"]?.textContent() ?? payload.textContent())
            guard !displayName.isEmpty || !detail.isEmpty else {
                return
            }
            toolActivities.append(CompressedToolActivity(title: displayName.isEmpty ? itemType : displayName, detail: detail))
            referencedFiles.insert(contentsOf: fileReferences(in: detail))
            visibleTokenEstimate += TokenEstimator.estimate(detail)
        case "function_call_output", "tool_search_output":
            let detail = trimmed(payload["output"]?.textContent() ?? payload.textContent())
            guard !detail.isEmpty else {
                return
            }
            toolActivities.append(CompressedToolActivity(title: itemType, detail: detail))
            referencedFiles.insert(contentsOf: fileReferences(in: detail))
            visibleTokenEstimate += TokenEstimator.estimate(detail)
        default:
            return
        }
    }

    private func mcpActivity(from payload: JSONValue) -> CompressedToolActivity {
        let server = payload["invocation"]?["server"]?.string ?? "mcp"
        let tool = payload["invocation"]?["tool"]?.string ?? "tool"
        let arguments = payload["invocation"]?["arguments"]?.textContent() ?? ""
        let result = payload["result"]?.textContent() ?? ""
        let detail = trimmed([arguments, result].filter { !$0.isEmpty }.joined(separator: "\n"))
        return CompressedToolActivity(title: "\(server).\(tool)", detail: detail)
    }

    private func messageContent(_ payload: JSONValue) -> String {
        guard let content = payload["content"] else {
            return ""
        }

        if let array = content.array {
            let textParts = array.compactMap { item in
                item["text"]?.string ?? item["input_text"]?.string ?? item["output_text"]?.string
            }
            if !textParts.isEmpty {
                return textParts.joined(separator: "\n")
            }
        }

        return content.textContent()
    }

    private func trimmed(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > options.maxTextCharacters else {
            return collapsed
        }

        let end = collapsed.index(collapsed.startIndex, offsetBy: options.maxTextCharacters)
        return String(collapsed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func fileReferences(in text: String) -> [String] {
        let patterns = [
            #"(/Users/[^\s"'\]\):,]+)"#,
            #"((?:\.{1,2}/)?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+\.[A-Za-z0-9_+-]+)"#
        ]
        var result = OrderedStrings()

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let fileRange = Range(match.range(at: 1), in: text) else {
                    continue
                }
                let raw = String(text[fileRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
                guard shouldTreatAsFile(raw) else {
                    continue
                }
                result.insert(raw)
            }
        }

        return result.values
    }

    private func shouldTreatAsFile(_ value: String) -> Bool {
        if value.contains("/SKILL.md") {
            return false
        }
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return false
        }
        let ignoredExtensions = ["jsonl"]
        let ext = URL(fileURLWithPath: value).pathExtension.lowercased()
        if ignoredExtensions.contains(ext) {
            return false
        }
        return value.contains("/")
    }
}

private struct OrderedStrings {
    private(set) var values: [String] = []
    private var seen: Set<String> = []

    mutating func insert(_ value: String) {
        guard seen.insert(value).inserted else {
            return
        }
        values.append(value)
    }

    mutating func insert(contentsOf values: [String]) {
        for value in values {
            insert(value)
        }
    }
}
