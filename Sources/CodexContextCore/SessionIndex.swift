import Foundation

struct SessionIndexEntry: Equatable {
    let id: String
    let threadName: String?
    let updatedAt: Date?
}

enum SessionIndex {
    static func load(codexHome: URL) -> [String: SessionIndexEntry] {
        let indexURL = codexHome.appendingPathComponent("session_index.jsonl")
        guard let text = try? String(contentsOf: indexURL, encoding: .utf8) else {
            return [:]
        }

        var entries: [String: SessionIndexEntry] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let json = JSONValue.parse(line: String(line)),
                  let id = json["id"]?.string else {
                continue
            }
            let entry = SessionIndexEntry(
                id: id,
                threadName: json["thread_name"]?.string,
                updatedAt: json["updated_at"]?.string.flatMap(DateParsers.parse)
            )
            entries[id] = entry
        }
        return entries
    }
}

enum DateParsers {
    static func parse(_ text: String) -> Date? {
        let fractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        let regular: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()

        return fractional.date(from: text) ?? regular.date(from: text)
    }
}
