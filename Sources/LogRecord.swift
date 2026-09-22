import Foundation
import Glider

internal enum LogLevel: String { case error, warning, info, debug
    var glider: Level {
        switch self { case .error: return .error; case .warning: return .warning
        case .info: return .info; case .debug: return .debug }
    }
}

internal enum LogSnapshot {
    static let limit = 32 * 1024
    static var marker: String { L10n.text("truncated") }

    static func text(_ value: String, limit: Int = limit) -> String {
        guard value.utf8.count > limit else { return value }
        let prefix = value.utf8.prefix(max(0, limit - marker.utf8.count))
        var bytes = Array(prefix)
        while String(bytes: bytes, encoding: .utf8) == nil && !bytes.isEmpty { bytes.removeLast() }
        return (String(bytes: bytes, encoding: .utf8) ?? "") + marker
    }

    static func context(_ value: [String: Any]) -> [String: Any] {
        var budget = limit
        let result = normalize(value, depth: 0, budget: &budget) as? [String: Any] ?? [:]
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              data.count <= limit else { return ["_truncated": L10n.text("contextTruncated")] }
        // Foundation containers are converted into immutable JSON value types before dispatch.
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func normalize(_ value: Any, depth: Int, budget: inout Int) -> Any {
        guard depth <= 8, budget > 0 else { return marker }
        budget -= 8
        if value is NSNull { return NSNull() }
        if let date = value as? Date { return ISO8601DateFormatter().string(from: date) }
        if let url = value as? URL { return text(url.absoluteString, limit: max(32, budget)) }
        if let string = value as? String {
            let clipped = text(string, limit: max(32, budget))
            budget -= clipped.utf8.count
            return clipped
        }
        if let number = value as? NSNumber {
            return number.doubleValue.isFinite ? number : String(describing: number)
        }
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, item) in dictionary {
                guard budget > 0 else { result["_truncated"] = marker; break }
                let safeKey = text(key, limit: min(1024, max(32, budget)))
                budget -= safeKey.utf8.count
                result[safeKey] = normalize(item, depth: depth + 1, budget: &budget)
            }
            return result
        }
        if let array = value as? [Any] {
            var result: [Any] = []
            for item in array {
                guard budget > 0 else { result.append(marker); break }
                result.append(normalize(item, depth: depth + 1, budget: &budget))
            }
            return result
        }
        let description = text(String(describing: value), limit: max(32, budget))
        budget -= description.utf8.count
        return description
    }
}

internal struct LogRecord {
    let timestamp: String
    let level: String
    let tag: String
    let message: String
    let context: [String: Any]
    let file: String
    let line: UInt

    init(level: LogLevel, tag: String, message: String, context: [String: Any], file: String = #fileID, line: UInt = #line) {
        timestamp = ISO8601DateFormatter.spark.string(from: Date())
        self.level = level.rawValue
        self.tag = LogSnapshot.text(tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Default" : tag, limit: 1024)
        self.message = LogSnapshot.text(message)
        self.context = LogSnapshot.context(context)
        self.file = LogSnapshot.text((file as NSString).lastPathComponent, limit: 1024)
        self.line = line
    }

    var object: [String: Any] {
        ["timestamp": timestamp, "level": level, "tag": tag, "message": message, "context": context, "file": file, "line": line]
    }
    var json: String { Wire.encode(object) }
}

internal enum Wire {
    static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
    static func decode(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    static func envelope(_ type: String, session: String, extra: [String: Any] = [:]) -> String {
        var object = extra
        object["version"] = 1; object["type"] = type; object["sessionID"] = session
        return encode(object)
    }
}

private extension ISO8601DateFormatter {
    static var spark: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

internal struct RawFormatter: EventMessageFormatter {
    func format(event: Event) -> SerializableData? { event.message.content }
}
internal struct ConsoleFormatter: EventMessageFormatter {
    func format(event: Event) -> SerializableData? {
        guard let json = Wire.decode(event.message.content) else { return nil }
        let context = json["context"] as? [String: Any] ?? [:]
        let suffix = context.isEmpty ? "" : " " + Wire.encode(context)
        let location: String
        if let file = json["file"] as? String, !file.isEmpty, let line = json["line"] as? NSNumber {
            location = " [\(file):\(line)]"
        } else { location = "" }
        return "[\(json["timestamp"] ?? "")] [\(json["level"] ?? "")] [\(json["tag"] ?? "")]\(location) \(json["message"] ?? "")\(suffix)"
    }
}

/// Bounded ring; confined to the service queue (main).
internal struct LogHistory {
    private var items: [[String: Any]] = []
    private var start = 0
    let capacity: Int
    init(capacity: Int = 2000) { self.capacity = capacity }
    mutating func append(_ item: [String: Any]) {
        if items.count < capacity { items.append(item) }
        else { items[start] = item; start = (start + 1) % capacity }
    }
    var values: [[String: Any]] { Array(items[start...]) + Array(items[..<start]) }
    mutating func clear() { items.removeAll(keepingCapacity: true); start = 0 }
}
