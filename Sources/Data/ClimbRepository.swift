import Foundation

/// All Turso queries live here - plain async functions, no view state.
/// Mirrors what app.py's /api/climbs, /api/board-info, /api/history,
/// /api/log-try, /api/log-ascent, /api/toggle-favorite used to do server
/// side, now run directly against Turso from the client.
final class ClimbRepository {
    private let db: TursoClient
    private let catalog: LocalCatalogStore

    init(db: TursoClient, catalog: LocalCatalogStore) {
        self.db = db
        self.catalog = catalog
    }

    /// Populates the local catalog cache on first launch only; a no-op on
    /// every launch after. Call refreshCatalog() explicitly to force a
    /// re-download (e.g. after re-running the export/sync scripts).
    func ensureCatalogReady() async throws {
        if await !catalog.isPopulated {
            try await refreshCatalog()
        }
    }

    func refreshCatalog() async throws {
        try await catalog.rebuild(from: db)
        invalidateProgressCache()
    }

    /// Local-time "yyyy-MM-ddTHH:mm:ss", no timezone suffix - matches
    /// exactly what the Python migration/export writes (Python's
    /// datetime.now().isoformat(timespec="seconds")). Using a different
    /// format for new entries would silently break date parsing/sorting
    /// for anything written from this app - already bit us once server-side.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Board info (fetched once at launch)

    func fetchBoardInfo() async throws -> BoardInfo {
        async let gradeRows = catalog.execute("SELECT difficulty, boulder_name FROM grades ORDER BY difficulty")
        async let angleRows = catalog.execute("SELECT angle FROM angles ORDER BY angle")
        async let colorRows = catalog.execute("SELECT role_id, hex, led_hex FROM colors")
        async let holdRows = catalog.execute("SELECT image_url, placement_id, mirrored_placement_id, x, y, led_position FROM holds")
        async let metaRows = catalog.execute("SELECT key, value FROM board_meta")

        let grades = try await gradeRows.compactMap { row -> (Int, String)? in
            guard let d = row["difficulty"]?.intValue, let n = row["boulder_name"]?.stringValue else { return nil }
            return (d, n)
        }
        let angles = try await angleRows.compactMap { $0["angle"]?.intValue }

        var colors: [Int: String] = [:]
        var ledColors: [Int: String] = [:]
        for row in try await colorRows {
            guard let id = row["role_id"]?.intValue else { continue }
            colors[id] = row["hex"]?.stringValue
            ledColors[id] = row["led_hex"]?.stringValue
        }

        var imagesByURL: [String: [BoardHold]] = [:]
        var imageOrder: [String] = []
        for row in try await holdRows {
            guard
                let url = row["image_url"]?.stringValue,
                let placementId = row["placement_id"]?.intValue,
                let x = row["x"]?.intValue,
                let y = row["y"]?.intValue
            else { continue }
            if imagesByURL[url] == nil {
                imagesByURL[url] = []
                imageOrder.append(url)
            }
            imagesByURL[url]?.append(
                BoardHold(
                    placementId: placementId,
                    mirroredPlacementId: row["mirrored_placement_id"]?.intValue,
                    x: x,
                    y: y,
                    ledPosition: row["led_position"]?.intValue
                )
            )
        }
        let images = imageOrder.map { BoardImage(url: $0, holds: imagesByURL[$0] ?? []) }

        var meta: [String: String] = [:]
        for row in try await metaRows {
            if let key = row["key"]?.stringValue, let value = row["value"]?.stringValue {
                meta[key] = value
            }
        }

        var placementPositions: [Int: Int] = [:]
        for row in try await holdRows {
            if let id = row["placement_id"]?.intValue, let position = row["led_position"]?.intValue {
                placementPositions[id] = position
            }
        }

        return BoardInfo(
            board: meta["board"] ?? "tension",
            appURL: meta["app_url"] ?? "",
            grades: grades,
            angles: angles,
            colors: colors,
            ledColors: ledColors,
            images: images,
            edgeLeft: Int(meta["edge_left"] ?? "0") ?? 0,
            edgeRight: Int(meta["edge_right"] ?? "0") ?? 0,
            edgeBottom: Int(meta["edge_bottom"] ?? "0") ?? 0,
            edgeTop: Int(meta["edge_top"] ?? "0") ?? 0,
            placementPositions: placementPositions
        )
    }

    // MARK: - Browsing

    struct Filters {
        var minGrade: Int
        var maxGrade: Int
        var angle: Int? // nil = any
        var onlyClassics = true
        var onlyFavorites = false
        var minAscents = 1
        var minQuality: Double = 1.0
        var name = ""
        var sortBy: SortField = .difficulty
        var ascending = true
    }

    enum SortField: String {
        case ascents = "ascensionist_count"
        case quality = "quality_average"
        case difficulty
        case name
    }

    func fetchClimbs(filters: Filters, page: Int, pageSize: Int) async throws -> (climbs: [Climb], total: Int) {
        var conditions = [
            "ROUND(difficulty) BETWEEN ? AND ?",
            "ascensionist_count >= ?",
            "quality_average >= ?",
        ]
        var args: [Any] = [filters.minGrade, filters.maxGrade, filters.minAscents, filters.minQuality]

        if filters.onlyClassics {
            conditions.append("benchmark_difficulty IS NOT NULL")
        }
        if let angle = filters.angle {
            conditions.append("angle = ?")
            args.append(angle)
        }
        if !filters.name.trimmingCharacters(in: .whitespaces).isEmpty {
            conditions.append("name LIKE ?")
            args.append("%\(filters.name)%")
        }

        var favoriteKeys: Set<String> = []
        if filters.onlyFavorites {
            favoriteKeys = try await fetchFavoriteKeys()
            guard !favoriteKeys.isEmpty else { return ([], 0) }
            let placeholders = favoriteKeys.map { _ in "(?, ?)" }.joined(separator: ", ")
            conditions.append("(uuid, angle) IN (VALUES \(placeholders))")
            for key in favoriteKeys {
                let parts = key.split(separator: ":")
                args.append(String(parts[0]))
                args.append(Int(parts[1]) ?? 0)
            }
        }

        let whereClause = conditions.joined(separator: " AND ")

        let countRows = try await catalog.execute("SELECT COUNT(*) AS n FROM climbs WHERE \(whereClause)", args: args)
        let total = countRows.first?["n"]?.intValue ?? 0

        let orderDirection = filters.ascending ? "ASC" : "DESC"
        let secondarySort = filters.sortBy == .ascents ? "" : ", ascensionist_count DESC"
        let sql = """
            SELECT * FROM climbs WHERE \(whereClause)
            ORDER BY \(filters.sortBy.rawValue) \(orderDirection)\(secondarySort)
            LIMIT ? OFFSET ?
        """
        let rows = try await catalog.execute(sql, args: args + [pageSize, page * pageSize])
        var climbs = rows.compactMap { Climb(row: $0) }

        try await mergeProgress(into: &climbs, favoriteKeys: filters.onlyFavorites ? favoriteKeys : nil)
        return (climbs, total)
    }

    private func mergeProgress(into climbs: inout [Climb], favoriteKeys: Set<String>?) async throws {
        guard !climbs.isEmpty else { return }

        let keys: Set<String>
        if let favoriteKeys {
            keys = favoriteKeys
        } else {
            keys = try await fetchFavoriteKeys()
        }
        let sendCounts = try await fetchSendCounts()
        let tries = try await fetchTries()

        for index in climbs.indices {
            let key = climbs[index].id
            climbs[index].sendCount = sendCounts[key] ?? 0
            climbs[index].sent = (sendCounts[key] ?? 0) > 0
            climbs[index].tries = tries[key] ?? 0
            climbs[index].favorited = keys.contains(key)
        }
    }

    // Cached in memory for the session - these three used to be refetched
    // from Turso on every single page/filter change, which is what made
    // paging feel laggy. Writes (below) keep the cache in sync with what
    // this device just did; invalidateProgressCache() forces a full
    // refetch (called after refreshCatalog(), so a manual refresh still
    // picks up anything changed from another device).
    private var favoriteKeysCache: Set<String>?
    private var sendCountsCache: [String: Int]?
    private var triesCache: [String: Int]?

    func invalidateProgressCache() {
        favoriteKeysCache = nil
        sendCountsCache = nil
        triesCache = nil
    }

    private func fetchFavoriteKeys() async throws -> Set<String> {
        if let favoriteKeysCache { return favoriteKeysCache }
        let rows = try await db.execute("SELECT climb_uuid, angle FROM favorites")
        let keys = Set(rows.compactMap { row -> String? in
            guard let uuid = row["climb_uuid"]?.stringValue, let angle = row["angle"]?.intValue else { return nil }
            return "\(uuid):\(angle)"
        })
        favoriteKeysCache = keys
        return keys
    }

    private func fetchSendCounts() async throws -> [String: Int] {
        if let sendCountsCache { return sendCountsCache }
        let rows = try await db.execute("SELECT climb_uuid, angle, COUNT(*) AS n FROM ascent_log GROUP BY climb_uuid, angle")
        var result: [String: Int] = [:]
        for row in rows {
            guard let uuid = row["climb_uuid"]?.stringValue, let angle = row["angle"]?.intValue else { continue }
            result["\(uuid):\(angle)"] = row["n"]?.intValue ?? 0
        }
        sendCountsCache = result
        return result
    }

    private func fetchTries() async throws -> [String: Int] {
        if let triesCache { return triesCache }
        let rows = try await db.execute("SELECT climb_uuid, angle, tries FROM tries")
        var result: [String: Int] = [:]
        for row in rows {
            guard let uuid = row["climb_uuid"]?.stringValue, let angle = row["angle"]?.intValue else { continue }
            result["\(uuid):\(angle)"] = row["tries"]?.intValue ?? 0
        }
        triesCache = result
        return result
    }

    // MARK: - Logging actions

    func logTry(uuid: String, angle: Int) async throws -> Int {
        try await db.execute(
            """
            INSERT INTO tries (climb_uuid, angle, tries) VALUES (?, ?, 1)
            ON CONFLICT (climb_uuid, angle) DO UPDATE SET tries = tries + 1
            """,
            args: [uuid, angle]
        )
        let rows = try await db.execute(
            "SELECT tries FROM tries WHERE climb_uuid = ? AND angle = ?",
            args: [uuid, angle]
        )
        let count = rows.first?["tries"]?.intValue ?? 0
        triesCache?["\(uuid):\(angle)"] = count
        return count
    }

    func logAscent(uuid: String, angle: Int) async throws -> Int {
        let now = Self.timestampFormatter.string(from: Date())
        try await db.execute(
            "INSERT INTO ascent_log (climb_uuid, angle, logged_at) VALUES (?, ?, ?)",
            args: [uuid, angle, now]
        )
        let rows = try await db.execute(
            "SELECT COUNT(*) AS n FROM ascent_log WHERE climb_uuid = ? AND angle = ?",
            args: [uuid, angle]
        )
        let count = rows.first?["n"]?.intValue ?? 0
        sendCountsCache?["\(uuid):\(angle)"] = count
        return count
    }

    func toggleFavorite(uuid: String, angle: Int) async throws -> Bool {
        let existing = try await db.execute(
            "SELECT 1 AS found FROM favorites WHERE climb_uuid = ? AND angle = ?",
            args: [uuid, angle]
        )
        let key = "\(uuid):\(angle)"
        if existing.isEmpty {
            try await db.execute("INSERT INTO favorites (climb_uuid, angle) VALUES (?, ?)", args: [uuid, angle])
            favoriteKeysCache?.insert(key)
            return true
        } else {
            try await db.execute("DELETE FROM favorites WHERE climb_uuid = ? AND angle = ?", args: [uuid, angle])
            favoriteKeysCache?.remove(key)
            return false
        }
    }

    // MARK: - Beta links

    func fetchBetaLinks(uuid: String, angle: Int) async throws -> [BetaLink] {
        let rows = try await catalog.execute(
            "SELECT link, foreign_username, thumbnail FROM beta_links WHERE climb_uuid = ? AND (angle = ? OR angle IS NULL)",
            args: [uuid, angle]
        )
        return rows.compactMap { BetaLink(row: $0) }
    }

    // MARK: - History

    /// ascent_log (personal, live) and climbs (catalog, now local-only) no
    /// longer live in the same database, so this joins them in Swift
    /// instead of SQL: one live Turso query for the log, one local catalog
    /// lookup for the climb names/grades.
    func fetchHistory() async throws -> [HistoryEntry] {
        let logRows = try await db.execute(
            "SELECT climb_uuid, angle, logged_at FROM ascent_log ORDER BY logged_at DESC"
        )
        guard !logRows.isEmpty else { return [] }

        let pairs = logRows.compactMap { row -> (String, Int)? in
            guard let uuid = row["climb_uuid"]?.stringValue, let angle = row["angle"]?.intValue else { return nil }
            return (uuid, angle)
        }
        let uniquePairs = Array(Set(pairs.map { "\($0.0):\($0.1)" })).map { key -> (String, Int) in
            let parts = key.split(separator: ":")
            return (String(parts[0]), Int(parts[1]) ?? 0)
        }
        let placeholders = uniquePairs.map { _ in "(?, ?)" }.joined(separator: ", ")
        let climbArgs = uniquePairs.flatMap { [$0.0, $0.1] }
        let climbRows = try await catalog.execute(
            "SELECT uuid, angle, name, grade, benchmark_difficulty FROM climbs WHERE (uuid, angle) IN (VALUES \(placeholders))",
            args: climbArgs
        )

        var climbInfo: [String: (name: String, grade: String?, isClassic: Bool)] = [:]
        for row in climbRows {
            guard let uuid = row["uuid"]?.stringValue, let angle = row["angle"]?.intValue, let name = row["name"]?.stringValue else { continue }
            climbInfo["\(uuid):\(angle)"] = (name, row["grade"]?.stringValue, row["benchmark_difficulty"]?.isNull == false)
        }

        return logRows.compactMap { row in
            guard
                let uuid = row["climb_uuid"]?.stringValue,
                let angle = row["angle"]?.intValue,
                let info = climbInfo["\(uuid):\(angle)"],
                let loggedAtString = row["logged_at"]?.stringValue,
                let loggedAt = Self.timestampFormatter.date(from: loggedAtString)
            else { return nil }
            return HistoryEntry(
                uuid: uuid,
                angle: angle,
                name: info.name,
                grade: info.grade,
                isClassic: info.isClassic,
                loggedAt: loggedAt
            )
        }
    }
}
