import Foundation
import Testing
@testable import CodexContextCore

@Test func tokenEstimatorHandlesMixedText() {
    #expect(TokenEstimator.estimate("hello world") >= 2)
    #expect(TokenEstimator.estimate("状态栏上下文") >= 4)
    #expect(TokenEstimator.estimate("") == 0)
}

@Test func analyzerBuildsBreakdownFromSessionFile() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-context-monitor-tests-\(UUID().uuidString)")
    let sessions = temp.appendingPathComponent("sessions/2026/06/14")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    let sessionID = "session-user"
    let session = sessions.appendingPathComponent("rollout-test-\(sessionID).jsonl")
    let index = temp.appendingPathComponent("session_index.jsonl")

    let meta: [String: Any] = [
        "timestamp": "2026-06-14T00:00:00.000Z",
        "type": "session_meta",
        "payload": [
            "id": sessionID,
            "timestamp": "2026-06-14T00:00:00.000Z",
            "cwd": "/tmp/project",
            "thread_source": "user",
            "base_instructions": [
                "text": "- build-web-apps:react-best-practices: React guidance (file: r4/react-best-practices/SKILL.md)"
            ],
            "dynamic_tools": [
                [
                    "namespace": "mcp__node_repl",
                    "name": "js",
                    "description": "Run JavaScript"
                ]
            ]
        ]
    ]
    let message: [String: Any] = [
        "timestamp": "2026-06-14T00:00:01.000Z",
        "type": "response_item",
        "payload": [
            "type": "message",
            "role": "user",
            "content": [
                ["type": "input_text", "text": "Open /Users/test/project/Sources/App.swift and use a Skill."]
            ]
        ]
    ]
    let tokenCount: [String: Any] = [
        "timestamp": "2026-06-14T00:00:02.000Z",
        "type": "event_msg",
        "payload": [
            "type": "token_count",
            "info": [
                "last_token_usage": [
                    "input_tokens": 200,
                    "cached_input_tokens": 50
                ],
                "total_token_usage": [
                    "total_tokens": 300
                ],
                "model_context_window": 1000
            ]
        ]
    ]

    try [meta, message, tokenCount]
        .map(jsonLine)
        .joined(separator: "\n")
        .write(to: session, atomically: true, encoding: .utf8)
    try #"{"id":"session-user","thread_name":"User Thread","updated_at":"2026-06-14T00:00:03.000000Z"}"#
        .write(to: index, atomically: true, encoding: .utf8)

    let analyzer = ContextAnalyzer(codexHome: temp)
    let snapshot = analyzer.snapshot()

    #expect(snapshot.session?.id == sessionID)
    #expect(snapshot.session?.name == "User Thread")
    #expect(snapshot.contextWindow == 1000)
    #expect(snapshot.lastInputTokens == 200)
    #expect(snapshot.categories.contains { $0.kind == .skills })
    #expect(snapshot.categories.contains { $0.kind == .mcp })
    #expect(snapshot.categories.contains { $0.kind == .files })
}

@Test func locatorIgnoresSubagentSessions() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-context-monitor-tests-\(UUID().uuidString)")
    let sessions = temp.appendingPathComponent("sessions/2026/06/14")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    let user = sessions.appendingPathComponent("rollout-user.jsonl")
    let subagent = sessions.appendingPathComponent("rollout-subagent.jsonl")
    let index = temp.appendingPathComponent("session_index.jsonl")

    try sessionMeta(id: "user-session", threadSource: "user")
        .write(to: user, atomically: true, encoding: .utf8)
    try sessionMeta(id: "subagent-session", threadSource: "subagent")
        .write(to: subagent, atomically: true, encoding: .utf8)
    try """
    {"id":"user-session","thread_name":"User","updated_at":"2026-06-14T00:00:01.000000Z"}
    {"id":"subagent-session","thread_name":"Subagent","updated_at":"2026-06-14T00:00:02.000000Z"}
    """
    .write(to: index, atomically: true, encoding: .utf8)

    let locator = SessionLocator(codexHome: temp)
    let selected = try locator.latestUserSession()
    #expect(selected.id == "user-session")
}

@Test func locatorListsRecentUserSessionsAndFindsSpecificSession() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-context-monitor-tests-\(UUID().uuidString)")
    let sessions = temp.appendingPathComponent("sessions/2026/06/14")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    try sessionMeta(id: "older", threadSource: "user")
        .write(to: sessions.appendingPathComponent("rollout-older.jsonl"), atomically: true, encoding: .utf8)
    try sessionMeta(id: "newer", threadSource: "user")
        .write(to: sessions.appendingPathComponent("rollout-newer.jsonl"), atomically: true, encoding: .utf8)
    try """
    {"id":"older","thread_name":"Older","updated_at":"2026-06-14T00:00:01.000000Z"}
    {"id":"newer","thread_name":"Newer","updated_at":"2026-06-14T00:00:02.000000Z"}
    """
    .write(to: temp.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)

    let locator = SessionLocator(codexHome: temp)
    let recent = try locator.recentUserSessions(limit: 10)

    #expect(recent.map(\.id) == ["newer", "older"])
    #expect(try locator.session(id: "older").name == "Older")
}

@Test func locatorFindsSpecificSessionByFileNameBeforeScanningEverything() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-context-monitor-tests-\(UUID().uuidString)")
    let sessions = temp.appendingPathComponent("sessions/2026/06/14")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    try "not json\n"
        .write(to: sessions.appendingPathComponent("rollout-unrelated.jsonl"), atomically: true, encoding: .utf8)
    try sessionMeta(id: "target-session", threadSource: "user")
        .write(to: sessions.appendingPathComponent("rollout-target-session.jsonl"), atomically: true, encoding: .utf8)
    try #"{"id":"target-session","thread_name":"Target","updated_at":"2026-06-14T00:00:02.000000Z"}"#
        .write(to: temp.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)

    let locator = SessionLocator(codexHome: temp)

    #expect(try locator.session(id: "target-session").name == "Target")
}

@Test func locatorRecentSessionsScansBoundedRecentCandidates() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-context-monitor-tests-\(UUID().uuidString)")
    let sessions = temp.appendingPathComponent("sessions/2026/06/14")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    for index in 0..<80 {
        let file = sessions.appendingPathComponent("rollout-noise-\(index).jsonl")
        try "not json\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
            ofItemAtPath: file.path
        )
    }

    try sessionMeta(id: "recent-user", threadSource: "user")
        .write(to: sessions.appendingPathComponent("rollout-recent-user.jsonl"), atomically: true, encoding: .utf8)
    try sessionMeta(id: "recent-subagent", threadSource: "subagent")
        .write(to: sessions.appendingPathComponent("rollout-recent-subagent.jsonl"), atomically: true, encoding: .utf8)
    try """
    {"id":"recent-user","thread_name":"Recent User","updated_at":"2026-06-14T00:00:03.000000Z"}
    {"id":"recent-subagent","thread_name":"Recent Subagent","updated_at":"2026-06-14T00:00:04.000000Z"}
    """
    .write(to: temp.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)

    let locator = SessionLocator(codexHome: temp)
    let recent = try locator.recentUserSessions(limit: 1)

    #expect(recent.map(\.id) == ["recent-user"])
}

@Test func analyzerExtractsMCPDefinitionsAndEvents() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-context-monitor-tests-\(UUID().uuidString)")
    let sessions = temp.appendingPathComponent("sessions/2026/06/14")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    let session = sessions.appendingPathComponent("rollout-mcp.jsonl")
    let developerMessage: [String: Any] = [
        "timestamp": "2026-06-14T00:00:01.000Z",
        "type": "response_item",
        "payload": [
            "type": "message",
            "role": "developer",
            "content": [
                [
                    "type": "input_text",
                    "text": """
                    ## Namespace: mcp__node_repl
                    ### Target channel: commentary
                    type js = (_: {
                    code: string
                    }) => any;
                    type js_reset = () => any;
                    """
                ]
            ]
        ]
    ]
    let mcpEvent: [String: Any] = [
        "timestamp": "2026-06-14T00:00:02.000Z",
        "type": "event_msg",
        "payload": [
            "type": "mcp_tool_call_end",
            "invocation": [
                "server": "node_repl",
                "tool": "js",
                "arguments": ["code": "1 + 1"]
            ],
            "result": ["Ok": ["content": [["type": "text", "text": "2"]]]]
        ]
    ]

    try [
        try sessionMeta(id: "mcp-session", threadSource: "user"),
        try jsonLine(developerMessage),
        try jsonLine(mcpEvent)
    ]
    .joined(separator: "\n")
    .write(to: session, atomically: true, encoding: .utf8)
    try #"{"id":"mcp-session","thread_name":"MCP","updated_at":"2026-06-14T00:00:03.000000Z"}"#
        .write(to: temp.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)

    let snapshot = ContextAnalyzer(codexHome: temp).snapshot()
    let mcp = try #require(snapshot.categories.first { $0.kind == .mcp })
    #expect(mcp.items.contains { $0.title == "mcp__node_repl.js" })
    #expect(mcp.items.contains { $0.title == "mcp__node_repl.js_reset" })
    #expect(mcp.items.contains { $0.title == "node_repl.js" })
}

@Test func analyzerAppliesClearBaselineToConversationBreakdownAndTokenDisplay() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-context-monitor-tests-\(UUID().uuidString)")
    let sessions = temp.appendingPathComponent("sessions/2026/06/14")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    let sessionID = "clear-session"
    let session = sessions.appendingPathComponent("rollout-clear.jsonl")
    let beforeMessage: [String: Any] = [
        "timestamp": "2026-06-14T00:00:01.000Z",
        "type": "response_item",
        "payload": [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": "old context"]]
        ]
    ]
    let firstTokenCount: [String: Any] = [
        "timestamp": "2026-06-14T00:00:02.000Z",
        "type": "event_msg",
        "payload": [
            "type": "token_count",
            "info": [
                "last_token_usage": ["input_tokens": 100, "cached_input_tokens": 40],
                "total_token_usage": ["total_tokens": 150],
                "model_context_window": 1000
            ]
        ]
    ]
    let afterMessage: [String: Any] = [
        "timestamp": "2026-06-14T00:00:03.000Z",
        "type": "response_item",
        "payload": [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": "new context"]]
        ]
    ]
    let secondTokenCount: [String: Any] = [
        "timestamp": "2026-06-14T00:00:04.000Z",
        "type": "event_msg",
        "payload": [
            "type": "token_count",
            "info": [
                "last_token_usage": ["input_tokens": 130, "cached_input_tokens": 45],
                "total_token_usage": ["total_tokens": 210],
                "model_context_window": 1000
            ]
        ]
    ]

    try [
        try sessionMeta(id: sessionID, threadSource: "user"),
        try jsonLine(beforeMessage),
        try jsonLine(firstTokenCount),
        try jsonLine(afterMessage),
        try jsonLine(secondTokenCount)
    ]
    .joined(separator: "\n")
    .write(to: session, atomically: true, encoding: .utf8)
    try #"{"id":"clear-session","thread_name":"Clear","updated_at":"2026-06-14T00:00:05.000000Z"}"#
        .write(to: temp.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)

    let analyzer = ContextAnalyzer(codexHome: temp)
    let selected = try SessionLocator(codexHome: temp).session(id: sessionID)
    let snapshot = try analyzer.snapshot(
        for: selected,
        baseline: ContextBaseline(
            sessionID: sessionID,
            lineCount: 3,
            lastInputTokens: 100,
            cachedInputTokens: 40,
            totalRunTokens: 150,
            clearedAt: Date(timeIntervalSince1970: 0)
        )
    )

    #expect(snapshot.lastInputTokens == 130)
    #expect(snapshot.usageRatio == 0.13)
    #expect(snapshot.displayInputTokens == 30)
    #expect(snapshot.displayUsageRatio == 0.03)
    #expect(snapshot.displayCachedInputTokens == 5)
    #expect(snapshot.displayTotalRunTokens == 60)
    #expect(snapshot.categories.first { $0.kind == .messages }?.items.contains { $0.title == "User" } == true)
}

@Test func compressorBuildsContinuationDraftFromCurrentSession() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-context-monitor-tests-\(UUID().uuidString)")
    let sessions = temp.appendingPathComponent("sessions/2026/06/14")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    let sessionID = "compress-session"
    let session = sessions.appendingPathComponent("rollout-compress.jsonl")
    let firstMessage: [String: Any] = [
        "timestamp": "2026-06-14T00:00:01.000Z",
        "type": "response_item",
        "payload": [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": "Please inspect /Users/test/project/Sources/App.swift."]]
        ]
    ]
    let assistantMessage: [String: Any] = [
        "timestamp": "2026-06-14T00:00:02.000Z",
        "type": "response_item",
        "payload": [
            "type": "message",
            "role": "assistant",
            "content": [["type": "output_text", "text": "The app needs a compact summary action."]]
        ]
    ]
    let secondMessage: [String: Any] = [
        "timestamp": "2026-06-14T00:00:03.000Z",
        "type": "response_item",
        "payload": [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": "Keep the latest request visible."]]
        ]
    ]
    let toolCall: [String: Any] = [
        "timestamp": "2026-06-14T00:00:04.000Z",
        "type": "response_item",
        "payload": [
            "type": "function_call",
            "namespace": "functions",
            "name": "exec_command",
            "arguments": ["cmd": "sed -n 1,20p Sources/App.swift"]
        ]
    ]
    let tokenCount: [String: Any] = [
        "timestamp": "2026-06-14T00:00:05.000Z",
        "type": "event_msg",
        "payload": [
            "type": "token_count",
            "info": [
                "last_token_usage": ["input_tokens": 500, "cached_input_tokens": 100],
                "total_token_usage": ["total_tokens": 700],
                "model_context_window": 2000
            ]
        ]
    ]

    try [
        try sessionMeta(id: sessionID, threadSource: "user"),
        try jsonLine(firstMessage),
        try jsonLine(assistantMessage),
        try jsonLine(secondMessage),
        try jsonLine(toolCall),
        try jsonLine(tokenCount)
    ]
    .joined(separator: "\n")
    .write(to: session, atomically: true, encoding: .utf8)

    let choice = SessionChoice(
        id: sessionID,
        name: "Compression",
        path: session,
        cwd: "/Users/test/project",
        updatedAt: Date(timeIntervalSince1970: 0)
    )
    let draft = try SessionCompressor(options: SessionCompressionOptions(maxRecentMessages: 2, maxTextCharacters: 48))
        .compress(session: choice)

    #expect(draft.sourceLineCount == 6)
    #expect(draft.sourceTokenEstimate == 500)
    #expect(draft.lastInputTokens == 500)
    #expect(draft.contextWindow == 2000)
    #expect(draft.latestUserMessages.map(\.text).contains("Keep the latest request visible."))
    #expect(draft.recentMessages.map(\.role) == ["assistant", "user"])
    #expect(draft.referencedFiles.contains("/Users/test/project/Sources/App.swift"))
    #expect(draft.recentToolActivities.contains { $0.title == "functions.exec_command" })
    #expect(draft.omittedMessageCount == 1)
}

@Test func compressorTruncatesLongMessageText() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-context-monitor-tests-\(UUID().uuidString)")
    let sessions = temp.appendingPathComponent("sessions/2026/06/14")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    let session = sessions.appendingPathComponent("rollout-truncate.jsonl")
    let message: [String: Any] = [
        "timestamp": "2026-06-14T00:00:01.000Z",
        "type": "response_item",
        "payload": [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": String(repeating: "a", count: 120)]]
        ]
    ]

    try [
        try sessionMeta(id: "truncate-session", threadSource: "user"),
        try jsonLine(message)
    ]
    .joined(separator: "\n")
    .write(to: session, atomically: true, encoding: .utf8)

    let choice = SessionChoice(
        id: "truncate-session",
        name: nil,
        path: session,
        cwd: nil,
        updatedAt: Date(timeIntervalSince1970: 0)
    )
    let draft = try SessionCompressor(options: SessionCompressionOptions(maxTextCharacters: 40))
        .compress(session: choice)

    #expect(draft.recentMessages.first?.text.count == 83)
    #expect(draft.recentMessages.first?.text.hasSuffix("...") == true)
}

private func sessionMeta(id: String, threadSource: String) throws -> String {
    try jsonLine([
        "timestamp": "2026-06-14T00:00:00.000Z",
        "type": "session_meta",
        "payload": [
            "id": id,
            "timestamp": "2026-06-14T00:00:00.000Z",
            "cwd": "/tmp/project",
            "thread_source": threadSource,
            "base_instructions": ["text": ""],
            "dynamic_tools": []
        ]
    ])
}

private func jsonLine(_ value: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
}
