import SwiftUI

/// Every hold is tappable; tapping builds a shared memory-game sequence and
/// mirrors it live on the physical board over Bluetooth (role 6 = blue, same
/// as the web app's plusOneSequence/PLUSONE_LED_ROLE).
struct PlusOneGameView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var bluetooth: BluetoothManager
    @State private var sequence: [Int] = []

    private static let ledRole = "6"

    private var litHolds: [Int: Color] {
        Dictionary(uniqueKeysWithValues: sequence.map { ($0, AppColors.plusOneDot) })
    }

    private var countText: String {
        switch sequence.count {
        case 0: return "No moves yet"
        case 1: return "1 move"
        default: return "\(sequence.count) moves"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            boardArea
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.bg)
        .task { if appState.boardInfo == nil { await appState.start() } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(countText).font(.system(size: 18, weight: .bold))
                Text("Player 1 picks a hold. Each next player repeats every move so far, then adds one more. Tap a hold to add it; tap the last one again to undo.")
                    .font(.caption)
                    .foregroundStyle(AppColors.inkSoft)
                if !bluetooth.status.isEmpty {
                    Text(bluetooth.status).font(.caption).foregroundStyle(AppColors.inkSoft)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Undo", action: undo).buttonStyle(.bordered)
                Button("Reset", action: reset).buttonStyle(.bordered)
            }
        }
    }

    private var boardArea: some View {
        Group {
            if let board = appState.boardInfo {
                BoardCanvasView(
                    images: board.images,
                    edgeLeft: board.edgeLeft,
                    edgeRight: board.edgeRight,
                    edgeBottom: board.edgeBottom,
                    edgeTop: board.edgeTop,
                    litHolds: litHolds,
                    onTapHold: { handleTap($0, board: board) }
                )
                .padding(16)
            } else if let error = appState.errorMessage {
                Text(error).foregroundStyle(AppColors.accent)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .background(AppColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func handleTap(_ holdId: Int, board: BoardInfo) {
        if sequence.last == holdId {
            sequence.removeLast()
        } else if sequence.contains(holdId) {
            return
        } else {
            sequence.append(holdId)
        }
        illuminate(board: board)
    }

    private func undo() {
        guard !sequence.isEmpty else { return }
        sequence.removeLast()
        if let board = appState.boardInfo { illuminate(board: board) }
    }

    private func reset() {
        guard !sequence.isEmpty else { return }
        sequence.removeAll()
        if let board = appState.boardInfo { illuminate(board: board) }
    }

    private func illuminate(board: BoardInfo) {
        let frames = sequence.map { "p\($0)r\(Self.ledRole)" }.joined()
        bluetooth.illuminate(frames: frames, placementPositions: board.placementPositions, ledColors: board.ledColors)
    }
}
