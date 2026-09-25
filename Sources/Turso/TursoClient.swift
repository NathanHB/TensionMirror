import Foundation

/// Minimal client for Turso's Hrana-over-HTTP API (`/v2/pipeline`). No
/// native libSQL SDK needed - it's just JSON over HTTPS, which URLSession
/// handles fine. One request per call (execute + close), which is simple
/// and plenty fast for this app's query volume.
enum TursoError: Error, LocalizedError {
    case badResponse
    case queryError(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected response from the database."
        case .queryError(let message): return message
        }
    }
}

enum TursoValue {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null

    var stringValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .integer(let i): return Int(i)
        case .real(let d): return Int(d)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .real(let d): return d
        case .integer(let i): return Double(i)
        default: return nil
        }
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Converts a plain Swift value (as passed to execute(sql:args:)) into
    /// a TursoValue - shared by TursoClient's HTTP encoding and
    /// LocalCatalogStore's SQLite3 binding.
    init(any value: Any) {
        switch value {
        case let v as TursoValue: self = v
        case let s as String: self = .text(s)
        case let i as Int: self = .integer(Int64(i))
        case let i as Int64: self = .integer(i)
        case let d as Double: self = .real(d)
        default: self = .null
        }
    }
}

typealias TursoRow = [String: TursoValue]

final class TursoClient {
    private let pipelineURL: URL
    private let token: String
    private let session = URLSession.shared

    init(url: String, token: String) {
        var httpURL = url
        if httpURL.hasPrefix("libsql://") {
            httpURL = "https://" + httpURL.dropFirst("libsql://".count)
        }
        self.pipelineURL = URL(string: httpURL)!.appendingPathComponent("v2/pipeline")
        self.token = token
    }

    @discardableResult
    func execute(_ sql: String, args: [Any] = []) async throws -> [TursoRow] {
        var request = URLRequest(url: pipelineURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "requests": [
                ["type": "execute", "stmt": ["sql": sql, "args": args.map(Self.encodeArg)]],
                ["type": "close"],
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TursoError.badResponse
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]],
            let first = results.first
        else {
            throw TursoError.badResponse
        }

        if first["type"] as? String == "error" {
            let message = (first["error"] as? [String: Any])?["message"] as? String
            throw TursoError.queryError(message ?? "Unknown database error")
        }

        guard
            let responseObj = first["response"] as? [String: Any],
            let result = responseObj["result"] as? [String: Any],
            let cols = result["cols"] as? [[String: Any]],
            let rows = result["rows"] as? [[[String: Any]]]
        else {
            return []
        }

        let columnNames = cols.map { $0["name"] as? String ?? "" }
        return rows.map { row in
            var dict: TursoRow = [:]
            for (index, cell) in row.enumerated() where index < columnNames.count {
                dict[columnNames[index]] = Self.decodeValue(cell)
            }
            return dict
        }
    }

    private static func decodeValue(_ cell: [String: Any]) -> TursoValue {
        switch cell["type"] as? String {
        case "text":
            return .text(cell["value"] as? String ?? "")
        case "integer":
            if let s = cell["value"] as? String, let i = Int64(s) { return .integer(i) }
            if let n = cell["value"] as? NSNumber { return .integer(n.int64Value) }
            return .integer(0)
        case "float":
            if let n = cell["value"] as? NSNumber { return .real(n.doubleValue) }
            return .real(0)
        default:
            return .null
        }
    }

    private static func encodeArg(_ value: Any) -> [String: Any] {
        switch value {
        case let s as String:
            return ["type": "text", "value": s]
        case let i as Int:
            return ["type": "integer", "value": String(i)]
        case let d as Double:
            return ["type": "float", "value": d]
        default:
            return ["type": "null"]
        }
    }
}
