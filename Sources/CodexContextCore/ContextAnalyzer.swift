import Foundation

public struct ContextAnalyzer {
    public let codexHome: URL
    public let locator: SessionLocator

    public init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    ) {
        self.codexHome = codexHome
        self.locator = SessionLocator(codexHome: codexHome)
    }

    public func snapshot() -> ContextSnapshot {
        do {
            let session = try locator.latestUserSession()
            return try snapshot(for: session, baseline: nil)
        } catch {
            return ContextSnapshot(
                session: nil,
                generatedAt: Date(),
                contextWindow: 0,
                lastInputTokens: 0,
                cachedInputTokens: 0,
                totalRunTokens: 0,
                categories: [],
                warnings: [(error as? LocalizedError)?.errorDescription ?? String(describing: error)]
            )
        }
    }

    public func snapshot(sessionID: String?, baseline: ContextBaseline? = nil) -> ContextSnapshot {
        guard let sessionID, !sessionID.isEmpty else {
            if let baseline {
                do {
                    let session = try locator.latestUserSession()
                    return try snapshot(for: session, baseline: baseline.sessionID == session.id ? baseline : nil)
                } catch {
                    return snapshot()
                }
            }
            return snapshot()
        }

        do {
            let session = try locator.session(id: sessionID)
            return try snapshot(for: session, baseline: baseline?.sessionID == session.id ? baseline : nil)
        } catch {
            var fallback = snapshot()
            let warning = "Selected session is no longer available. Showing latest session."
            fallback = ContextSnapshot(
                session: fallback.session,
                generatedAt: fallback.generatedAt,
                contextWindow: fallback.contextWindow,
                lastInputTokens: fallback.lastInputTokens,
                cachedInputTokens: fallback.cachedInputTokens,
                totalRunTokens: fallback.totalRunTokens,
                categories: fallback.categories,
                warnings: fallback.warnings + [warning],
                baseline: fallback.baseline
            )
            return fallback
        }
    }

    public func recentSessions(limit: Int = 20) -> [SessionChoice] {
        (try? locator.recentUserSessions(limit: limit)) ?? []
    }

    public func snapshot(for session: SessionChoice, baseline: ContextBaseline? = nil) throws -> ContextSnapshot {
        guard let text = try? String(contentsOf: session.path, encoding: .utf8) else {
            throw ContextMonitorError.unreadableSession(session.path)
        }

        var accumulator = CategoryAccumulator()
        var contextWindow = 0
        var lastInputTokens = 0
        var cachedInputTokens = 0
        var totalRunTokens = 0
        var warnings: [String] = []

        for (lineIndex, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard let event = JSONValue.parse(line: String(line)),
                  let type = event["type"]?.string else {
                continue
            }

            let lineNumber = lineIndex + 1
            let includeInBreakdown = shouldIncludeInBreakdown(event: event, lineNumber: lineNumber, baseline: baseline)

            switch type {
            case "session_meta":
                if let payload = event["payload"] {
                    consumeSessionMeta(payload, into: &accumulator)
                }
            case "response_item":
                if includeInBreakdown, let payload = event["payload"] {
                    consumeResponseItem(payload, into: &accumulator)
                }
            case "event_msg":
                if let payload = event["payload"],
                   payload["type"]?.string == "token_count",
                   let info = payload["info"] {
                    contextWindow = info["model_context_window"]?.int ?? contextWindow
                    lastInputTokens = info["last_token_usage"]?["input_tokens"]?.int ?? lastInputTokens
                    cachedInputTokens = info["last_token_usage"]?["cached_input_tokens"]?.int ?? cachedInputTokens
                    totalRunTokens = info["total_token_usage"]?["total_tokens"]?.int ?? totalRunTokens
                } else if let payload = event["payload"],
                          includeInBreakdown,
                          payload["type"]?.string == "mcp_tool_call_end" {
                    consumeMCPEvent(payload, into: &accumulator)
                }
            default:
                break
            }
        }

        let categories = accumulator.categories()
        if lastInputTokens == 0 {
            warnings.append("No token_count event has been recorded for this session yet.")
        }

        return ContextSnapshot(
            session: session,
            generatedAt: Date(),
            contextWindow: contextWindow,
            lastInputTokens: lastInputTokens,
            cachedInputTokens: cachedInputTokens,
            totalRunTokens: totalRunTokens,
            categories: categories,
            warnings: warnings,
            baseline: baseline
        )
    }

    private func shouldIncludeInBreakdown(event: JSONValue, lineNumber: Int, baseline: ContextBaseline?) -> Bool {
        guard let baseline else {
            return true
        }
        guard lineNumber <= baseline.lineCount else {
            return true
        }

        if event["type"]?.string == "response_item",
           event["payload"]?["type"]?.string == "message",
           event["payload"]?["role"]?.string == "developer" {
            return true
        }

        return false
    }

    private func consumeSessionMeta(_ payload: JSONValue, into accumulator: inout CategoryAccumulator) {
        if let baseInstructions = payload["base_instructions"]?["text"]?.string, !baseInstructions.isEmpty {
            accumulator.add(
                kind: .instructions,
                title: "Base instructions",
                subtitle: nil,
                text: baseInstructions
            )
            extractSkills(from: baseInstructions, into: &accumulator)
        }

        let dynamicTools = payload["dynamic_tools"]?.array ?? []
        for tool in dynamicTools {
            let namespace = tool["namespace"]?.string ?? "tools"
            let name = tool["name"]?.string ?? "unknown"
            let description = tool["description"]?.string ?? ""
            let displayName = namespace.isEmpty ? name : "\(namespace).\(name)"
            let kind: ContextCategoryKind = isMCPNamespace(namespace) ? .mcp : .toolCalls

            accumulator.add(
                kind: kind,
                title: displayName,
                subtitle: "available tool",
                text: "\(displayName)\n\(description)"
            )
        }
    }

    private func consumeResponseItem(_ payload: JSONValue, into accumulator: inout CategoryAccumulator) {
        guard let itemType = payload["type"]?.string else {
            return
        }

        switch itemType {
        case "message":
            let role = payload["role"]?.string ?? "message"
            let content = messageContent(payload)
            accumulator.add(
                kind: role == "developer" ? .instructions : .messages,
                title: role.capitalized,
                subtitle: nil,
                text: content
            )
            extractFileReferences(from: content, into: &accumulator)
            extractSkills(from: content, into: &accumulator)
            extractMCPDefinitions(from: content, into: &accumulator)
        case "function_call":
            let namespace = payload["namespace"]?.string
            let name = payload["name"]?.string ?? "function_call"
            let displayName = [namespace, name].compactMap { $0 }.joined(separator: ".")
            let arguments = payload["arguments"]?.textContent() ?? ""
            let kind: ContextCategoryKind = namespace.map(isMCPNamespace) == true ? .mcp : .toolCalls
            accumulator.add(kind: kind, title: displayName, subtitle: "call", text: "\(displayName)\n\(arguments)")
            extractFileReferences(from: arguments, into: &accumulator)
        case "function_call_output", "tool_search_output":
            let output = payload["output"]?.textContent() ?? payload.textContent()
            accumulator.add(kind: .toolOutput, title: itemType, subtitle: nil, text: output)
            extractFileReferences(from: output, into: &accumulator)
            extractSkills(from: output, into: &accumulator)
        case "tool_search_call":
            let content = payload.textContent()
            accumulator.add(kind: .toolCalls, title: "tool_search", subtitle: "call", text: content)
        case "reasoning":
            let content = payload["summary"]?.textContent() ?? ""
            let encrypted = payload["encrypted_content"]?.string ?? ""
            let text = content.isEmpty ? encrypted : content
            accumulator.add(kind: .reasoning, title: "Reasoning", subtitle: nil, text: text)
        default:
            accumulator.add(kind: .other, title: itemType, subtitle: nil, text: payload.textContent())
        }
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

    private func consumeMCPEvent(_ payload: JSONValue, into accumulator: inout CategoryAccumulator) {
        let server = payload["invocation"]?["server"]?.string ?? "mcp"
        let tool = payload["invocation"]?["tool"]?.string ?? "tool"
        let arguments = payload["invocation"]?["arguments"]?.textContent() ?? ""
        let result = payload["result"]?.textContent() ?? ""
        accumulator.add(
            kind: .mcp,
            title: "\(server).\(tool)",
            subtitle: "call result",
            text: "\(server).\(tool)\n\(arguments)\n\(result)"
        )
    }

    private func extractSkills(from text: String, into accumulator: inout CategoryAccumulator) {
        let patterns = [
            #"(?m)^-\s+([A-Za-z0-9:_-]+):\s+.+?\(file:\s+([^)]+/SKILL\.md)\)"#,
            #"([A-Za-z0-9:_-]+/SKILL\.md)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                let title: String
                let subtitle: String?
                if match.numberOfRanges >= 3,
                   let nameRange = Range(match.range(at: 1), in: text),
                   let pathRange = Range(match.range(at: 2), in: text) {
                    title = String(text[nameRange])
                    subtitle = String(text[pathRange])
                } else if let pathRange = Range(match.range(at: 1), in: text) {
                    let path = String(text[pathRange])
                    title = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
                    subtitle = path
                } else {
                    continue
                }
                accumulator.add(kind: .skills, title: title, subtitle: subtitle, text: "\(title)\n\(subtitle ?? "")")
            }
        }
    }

    private func extractMCPDefinitions(from text: String, into accumulator: inout CategoryAccumulator) {
        guard text.contains("mcp__") else {
            return
        }

        guard let namespaceRegex = try? NSRegularExpression(pattern: #"(?m)^\s*## Namespace:\s+(mcp__[A-Za-z0-9_]+)\s*$"#),
              let toolRegex = try? NSRegularExpression(pattern: #"(?m)^\s*type\s+([A-Za-z_][A-Za-z0-9_]*)\s*="#) else {
            return
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let namespaces = namespaceRegex.matches(in: text, range: fullRange)
        guard !namespaces.isEmpty else {
            return
        }

        for (index, namespaceMatch) in namespaces.enumerated() {
            guard let namespaceRange = Range(namespaceMatch.range(at: 1), in: text) else {
                continue
            }

            let namespace = String(text[namespaceRange])
            let blockStart = namespaceMatch.range.location
            let blockEnd = index + 1 < namespaces.count ? namespaces[index + 1].range.location : fullRange.length
            let blockRange = NSRange(location: blockStart, length: blockEnd - blockStart)

            let tools = toolRegex.matches(in: text, range: blockRange)
            if tools.isEmpty {
                guard let range = Range(blockRange, in: text) else { continue }
                accumulator.add(kind: .mcp, title: namespace, subtitle: "tool namespace", text: String(text[range]))
                continue
            }

            for (toolIndex, toolMatch) in tools.enumerated() {
                guard let toolRange = Range(toolMatch.range(at: 1), in: text) else {
                    continue
                }

                let segmentStart = toolMatch.range.location
                let segmentEnd = toolIndex + 1 < tools.count ? tools[toolIndex + 1].range.location : blockEnd
                guard segmentEnd > segmentStart,
                      let segmentRange = Range(NSRange(location: segmentStart, length: segmentEnd - segmentStart), in: text) else {
                    continue
                }

                let tool = String(text[toolRange])
                accumulator.add(
                    kind: .mcp,
                    title: "\(namespace).\(tool)",
                    subtitle: "tool definition",
                    text: String(text[segmentRange])
                )
            }
        }
    }

    private func extractFileReferences(from text: String, into accumulator: inout CategoryAccumulator) {
        let patterns = [
            #"(/Users/[^\s"'\]\):,]+)"#,
            #"((?:\.{1,2}/)?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+\.[A-Za-z0-9_+-]+)"#
        ]

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
                accumulator.add(kind: .files, title: shortenPath(raw), subtitle: raw, text: raw)
            }
        }
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

    private func shortenPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let last = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? last : "\(parent)/\(last)"
    }

    private func isMCPNamespace(_ namespace: String) -> Bool {
        namespace.hasPrefix("mcp__") || namespace.hasPrefix("mcp_") || namespace.contains("mcp")
    }
}

private struct CategoryAccumulator {
    private var buckets: [ContextCategoryKind: [String: AccumulatedItem]] = [:]

    mutating func add(kind: ContextCategoryKind, title: String, subtitle: String?, text: String) {
        let normalizedTitle = title.isEmpty ? kind.rawValue : title
        let key = "\(normalizedTitle)\u{1F}\(subtitle ?? "")"
        var item = buckets[kind, default: [:]][key] ?? AccumulatedItem(
            title: normalizedTitle,
            subtitle: subtitle,
            tokens: 0,
            count: 0
        )
        item.tokens += TokenEstimator.estimate(text)
        item.count += 1
        buckets[kind, default: [:]][key] = item
    }

    func categories() -> [ContextCategory] {
        ContextCategoryKind.allCases.compactMap { kind in
            guard let values = buckets[kind], !values.isEmpty else {
                return nil
            }

            let items = values.values
                .map { ContextItem(title: $0.title, subtitle: $0.subtitle, tokens: $0.tokens, count: $0.count) }
                .sorted {
                    if $0.tokens == $1.tokens {
                        $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    } else {
                        $0.tokens > $1.tokens
                    }
                }

            return ContextCategory(
                kind: kind,
                tokens: items.reduce(0) { $0 + $1.tokens },
                items: items
            )
        }
        .sorted {
            if $0.kind.sortOrder == $1.kind.sortOrder {
                $0.tokens > $1.tokens
            } else {
                $0.kind.sortOrder < $1.kind.sortOrder
            }
        }
    }
}

private struct AccumulatedItem {
    let title: String
    let subtitle: String?
    var tokens: Int
    var count: Int
}
