import Foundation

struct Climb: Identifiable, Equatable {
    let uuid: String
    let angle: Int
    var id: String { "\(uuid):\(angle)" }

    let name: String
    let description: String?
    let frames: String
    let setterUsername: String?
    let ascensionistCount: Int
    let difficulty: Int?
    let grade: String?
    let qualityAverage: Double?
    let gradeError: Double?
    let benchmarkDifficulty: Double?

    var sent = false
    var sendCount = 0
    var tries = 0
    var favorited = false

    var isClassic: Bool { benchmarkDifficulty != nil }

    init?(row: TursoRow) {
        guard
            let uuid = row["uuid"]?.stringValue,
            let angle = row["angle"]?.intValue,
            let name = row["name"]?.stringValue,
            let frames = row["frames"]?.stringValue,
            let ascensionistCount = row["ascensionist_count"]?.intValue
        else { return nil }

        self.uuid = uuid
        self.angle = angle
        self.name = name
        self.description = row["description"]?.stringValue
        self.frames = frames
        self.setterUsername = row["setter_username"]?.stringValue
        self.ascensionistCount = ascensionistCount
        self.difficulty = row["difficulty"]?.intValue
        self.grade = row["grade"]?.stringValue
        self.qualityAverage = row["quality_average"]?.doubleValue
        self.gradeError = row["grade_error"]?.doubleValue
        self.benchmarkDifficulty = row["benchmark_difficulty"]?.isNull == false
            ? row["benchmark_difficulty"]?.doubleValue
            : nil
    }
}

/// One climb+angle pair, as logged in ascent_log - used by the History tab.
struct HistoryEntry: Identifiable {
    let id = UUID()
    let uuid: String
    let angle: Int
    let name: String
    let grade: String?
    let isClassic: Bool
    let loggedAt: Date
}

/// A video beta link another climber posted for this climb (mostly
/// Instagram). There's no real text-comment data in Aurora for this board -
/// every ascent's `comment` field came back empty when checked - so this is
/// the closest equivalent: other climbers' actual beta.
struct BetaLink: Identifiable {
    var id: String { link }
    let link: String
    let foreignUsername: String?
    let thumbnail: String?

    init?(row: TursoRow) {
        guard let link = row["link"]?.stringValue else { return nil }
        self.link = link
        self.foreignUsername = row["foreign_username"]?.stringValue
        self.thumbnail = row["thumbnail"]?.stringValue
    }
}
