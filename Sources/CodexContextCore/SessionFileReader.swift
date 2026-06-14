import Foundation

enum SessionFileReader {
    static func readSessionMeta(from file: URL) -> SessionMeta? {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return nil
        }
        defer { try? handle.close() }

        var buffer = Data()
        var bytesRead = 0
        let maxBytes = 512 * 1024

        while bytesRead < maxBytes {
            guard let chunk = try? handle.read(upToCount: min(64 * 1024, maxBytes - bytesRead)),
                  !chunk.isEmpty else {
                break
            }

            bytesRead += chunk.count
            buffer.append(chunk)

            if let meta = parseCompleteLines(from: &buffer) {
                return meta
            }
        }

        if let prefix = String(data: buffer, encoding: .utf8) {
            for line in prefix.split(separator: "\n", omittingEmptySubsequences: true) {
                if let meta = parseMetaLine(String(line)) {
                    return meta
                }
            }
        }

        return nil
    }

    private static func parseCompleteLines(from buffer: inout Data) -> SessionMeta? {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)

            guard !lineData.isEmpty,
                  let line = String(data: lineData, encoding: .utf8) else {
                continue
            }

            if let meta = parseMetaLine(line) {
                return meta
            }
        }

        return nil
    }

    private static func parseMetaLine(_ line: String) -> SessionMeta? {
        guard let json = JSONValue.parse(line: line),
              json["type"]?.string == "session_meta",
              let payload = json["payload"] else {
            return nil
        }
        return parseMeta(payload)
    }

    static func parseMeta(_ payload: JSONValue) -> SessionMeta? {
        guard let id = payload["id"]?.string else {
            return nil
        }

        let timestamp = payload["timestamp"]?.string.flatMap(DateParsers.parse)
        let cwd = payload["cwd"]?.string
        let threadSource = payload["thread_source"]?.string ?? "unknown"
        let baseInstructions = payload["base_instructions"]?["text"]?.string ?? ""
        let dynamicTools = payload["dynamic_tools"]?.array?.compactMap(parseTool) ?? []

        return SessionMeta(
            id: id,
            timestamp: timestamp,
            cwd: cwd,
            threadSource: threadSource,
            baseInstructions: baseInstructions,
            dynamicTools: dynamicTools
        )
    }

    private static func parseTool(_ value: JSONValue) -> DynamicTool? {
        guard let name = value["name"]?.string else {
            return nil
        }
        return DynamicTool(
            namespace: value["namespace"]?.string ?? "",
            name: name,
            description: value["description"]?.string ?? ""
        )
    }
}
