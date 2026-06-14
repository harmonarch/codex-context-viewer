import Foundation

enum JSONValue: Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(_ raw: Any) {
        switch raw {
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues { JSONValue($0) })
        case let array as [Any]:
            self = .array(array.map { JSONValue($0) })
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case is NSNull:
            self = .null
        default:
            self = .string(String(describing: raw))
        }
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var int: Int? {
        switch self {
        case .number(let value): Int(value)
        case .string(let value): Int(value)
        default: nil
        }
    }

    subscript(key: String) -> JSONValue? {
        object?[key]
    }

    func textContent() -> String {
        switch self {
        case .object(let dictionary):
            return dictionary
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.textContent())" }
                .joined(separator: "\n")
        case .array(let array):
            return array.map { $0.textContent() }.joined(separator: "\n")
        case .string(let string):
            return string
        case .number(let double):
            return String(double)
        case .bool(let bool):
            return String(bool)
        case .null:
            return ""
        }
    }

    static func parse(line: String) -> JSONValue? {
        guard let data = line.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return JSONValue(raw)
    }
}
