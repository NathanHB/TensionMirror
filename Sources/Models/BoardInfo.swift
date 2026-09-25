import Foundation

struct BoardHold: Identifiable {
    var id: Int { placementId }
    let placementId: Int
    let mirroredPlacementId: Int?
    let x: Int
    let y: Int
    let ledPosition: Int?
}

struct BoardImage: Identifiable {
    var id: String { url }
    let url: String
    let holds: [BoardHold]
}

struct BoardInfo {
    let board: String
    let appURL: String
    let grades: [(difficulty: Int, name: String)]
    let angles: [Int]
    let colors: [Int: String] // role_id -> "#RRGGBB", for the on-screen highlight
    let ledColors: [Int: String] // role_id -> "RRGGBB" (no #), for the Bluetooth packet
    let images: [BoardImage]
    let edgeLeft: Int
    let edgeRight: Int
    let edgeBottom: Int
    let edgeTop: Int
    let placementPositions: [Int: Int] // placement_id -> LED index

    var minGrade: Int { grades.first?.difficulty ?? 0 }
    var maxGrade: Int { grades.last?.difficulty ?? 99 }

    func gradeName(for difficulty: Int?) -> String? {
        guard let difficulty else { return nil }
        return grades.first { $0.difficulty == difficulty }?.name
    }
}
