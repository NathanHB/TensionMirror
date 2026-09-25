import Foundation
import SQLite3

/// On-device SQLite cache of the board catalog (climbs, holds, grades,
/// colors, board_meta, beta_links) - the largely-static data that used to
/// mean a live Turso round trip on every browse/filter/tap. Personal
/// progress (favorites/tries/ascent_log) deliberately stays live against
/// Turso in ClimbRepository - it's small per-request and needs to stay in
/// sync between the Mac and iPhone, so it's not cached here.
///
/// Same flat schema as Turso (see scripts/export_to_turso.py) and the same
/// TursoRow/TursoValue result shape, so ClimbRepository's row-decoding code
/// (Climb(row:), BoardHold, etc.) works unchanged against either backend.
actor LocalCatalogStore {
    private var db: OpaquePointer?
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TensionMirror", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("catalog.sqlite")
    }

    private func open() throws -> OpaquePointer {
        if let db { return db }
        var handle: OpaquePointer?
        guard sqlite3_open(fileURL.path, &handle) == SQLITE_OK, let handle else {
            throw LocalCatalogError.openFailed
        }
        db = handle
        return handle
    }

    var isPopulated: Bool {
        (try? execute("SELECT COUNT(*) AS n FROM climbs").first?["n"]?.intValue ?? 0) ?? 0 > 0
    }

    // MARK: - Query (mirrors TursoClient.execute's shape)

    @discardableResult
    func execute(_ sql: String, args: [Any] = []) throws -> [TursoRow] {
        let handle = try open()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw LocalCatalogError.sql(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }

        for (index, arg) in args.enumerated() {
            bind(TursoValue(any: arg), to: stmt, at: Int32(index + 1))
        }

        var rows: [TursoRow] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw LocalCatalogError.sql(String(cString: sqlite3_errmsg(handle)))
            }
            rows.append(readRow(stmt))
        }
        return rows
    }

    /// Prepares once, binds/steps/resets per row, all inside one
    /// transaction - used by rebuild() for bulk inserts of up to ~12k rows
    /// (beta_links) without the per-statement overhead of a fresh prepare.
    private func executeMany(_ sql: String, rows: [[TursoValue]]) throws {
        guard !rows.isEmpty else { return }
        let handle = try open()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw LocalCatalogError.sql(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }

        for row in rows {
            for (index, value) in row.enumerated() {
                bind(value, to: stmt, at: Int32(index + 1))
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw LocalCatalogError.sql(String(cString: sqlite3_errmsg(handle)))
            }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
    }

    private func bind(_ value: TursoValue, to stmt: OpaquePointer, at index: Int32) {
        switch value {
        case .text(let s):
            sqlite3_bind_text(stmt, index, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        case .integer(let i):
            sqlite3_bind_int64(stmt, index, i)
        case .real(let d):
            sqlite3_bind_double(stmt, index, d)
        case .null:
            sqlite3_bind_null(stmt, index)
        }
    }

    private func readRow(_ stmt: OpaquePointer) -> TursoRow {
        var row: TursoRow = [:]
        let columnCount = sqlite3_column_count(stmt)
        for i in 0..<columnCount {
            let name = String(cString: sqlite3_column_name(stmt, i))
            switch sqlite3_column_type(stmt, i) {
            case SQLITE_INTEGER:
                row[name] = .integer(sqlite3_column_int64(stmt, i))
            case SQLITE_FLOAT:
                row[name] = .real(sqlite3_column_double(stmt, i))
            case SQLITE_TEXT:
                row[name] = .text(String(cString: sqlite3_column_text(stmt, i)))
            default:
                row[name] = .null
            }
        }
        return row
    }

    // MARK: - Rebuild from Turso

    private static let schema = """
        DROP TABLE IF EXISTS climbs;
        DROP TABLE IF EXISTS grades;
        DROP TABLE IF EXISTS angles;
        DROP TABLE IF EXISTS colors;
        DROP TABLE IF EXISTS holds;
        DROP TABLE IF EXISTS board_meta;
        DROP TABLE IF EXISTS beta_links;

        CREATE TABLE climbs (
            uuid TEXT NOT NULL, angle INTEGER NOT NULL, name TEXT NOT NULL,
            description TEXT, frames TEXT NOT NULL, setter_username TEXT,
            ascensionist_count INTEGER NOT NULL, difficulty INTEGER, grade TEXT,
            quality_average REAL, grade_error REAL, benchmark_difficulty REAL,
            PRIMARY KEY (uuid, angle)
        );
        CREATE INDEX idx_climbs_difficulty ON climbs(difficulty);
        CREATE INDEX idx_climbs_angle ON climbs(angle);
        CREATE INDEX idx_climbs_ascents ON climbs(ascensionist_count);
        CREATE INDEX idx_climbs_quality ON climbs(quality_average);
        CREATE INDEX idx_climbs_name ON climbs(name);

        CREATE TABLE grades (difficulty INTEGER PRIMARY KEY, boulder_name TEXT NOT NULL);
        CREATE TABLE angles (angle INTEGER PRIMARY KEY);
        CREATE TABLE colors (role_id INTEGER PRIMARY KEY, hex TEXT NOT NULL, led_hex TEXT);
        CREATE TABLE holds (
            image_url TEXT NOT NULL, placement_id INTEGER NOT NULL,
            mirrored_placement_id INTEGER, x INTEGER NOT NULL, y INTEGER NOT NULL,
            led_position INTEGER, PRIMARY KEY (image_url, placement_id)
        );
        CREATE TABLE board_meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE beta_links (
            climb_uuid TEXT NOT NULL, angle INTEGER, link TEXT NOT NULL,
            foreign_username TEXT, thumbnail TEXT, PRIMARY KEY (climb_uuid, link)
        );
        CREATE INDEX idx_beta_links_climb ON beta_links(climb_uuid);
        """

    /// Wipes and repopulates the local cache from Turso - the only place
    /// this app talks to Turso for catalog data. Call once on first launch
    /// (no local cache yet) and whenever the user asks to refresh.
    func rebuild(from turso: TursoClient) async throws {
        let handle = try open()
        guard sqlite3_exec(handle, "PRAGMA foreign_keys = OFF", nil, nil, nil) == SQLITE_OK else {
            throw LocalCatalogError.sql(String(cString: sqlite3_errmsg(handle)))
        }
        guard sqlite3_exec(handle, Self.schema, nil, nil, nil) == SQLITE_OK else {
            throw LocalCatalogError.sql(String(cString: sqlite3_errmsg(handle)))
        }

        let tables: [(name: String, columns: [String])] = [
            ("climbs", ["uuid", "angle", "name", "description", "frames", "setter_username", "ascensionist_count", "difficulty", "grade", "quality_average", "grade_error", "benchmark_difficulty"]),
            ("grades", ["difficulty", "boulder_name"]),
            ("angles", ["angle"]),
            ("colors", ["role_id", "hex", "led_hex"]),
            ("holds", ["image_url", "placement_id", "mirrored_placement_id", "x", "y", "led_position"]),
            ("board_meta", ["key", "value"]),
            ("beta_links", ["climb_uuid", "angle", "link", "foreign_username", "thumbnail"]),
        ]

        guard sqlite3_exec(handle, "BEGIN TRANSACTION", nil, nil, nil) == SQLITE_OK else {
            throw LocalCatalogError.sql(String(cString: sqlite3_errmsg(handle)))
        }
        do {
            for table in tables {
                let remoteRows = try await turso.execute("SELECT \(table.columns.joined(separator: ", ")) FROM \(table.name)")
                let values = remoteRows.map { row in table.columns.map { row[$0] ?? .null } }
                let placeholders = table.columns.map { _ in "?" }.joined(separator: ", ")
                try executeMany(
                    "INSERT INTO \(table.name) (\(table.columns.joined(separator: ", "))) VALUES (\(placeholders))",
                    rows: values
                )
            }
        } catch {
            sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
            throw error
        }
        guard sqlite3_exec(handle, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            throw LocalCatalogError.sql(String(cString: sqlite3_errmsg(handle)))
        }
    }
}

enum LocalCatalogError: Error, LocalizedError {
    case openFailed
    case sql(String)

    var errorDescription: String? {
        switch self {
        case .openFailed: return "Couldn't open the local catalog cache."
        case .sql(let message): return message
        }
    }
}
