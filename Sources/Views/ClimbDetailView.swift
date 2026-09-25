import SwiftUI

/// Modal "viewer" (presented as a sheet), matching the web app's
/// `.viewer-backdrop` overlay: board image + info side by side on wide
/// screens, stacked on narrow ones.
struct ClimbDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss
    let climb: Climb
    @State private var betaLinks: [BetaLink] = []

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var useTwoColumn: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private var currentClimb: Climb {
        appState.climbs.first(where: { $0.id == climb.id }) ?? climb
    }

    var body: some View {
        Group {
            if useTwoColumn {
                HStack(alignment: .top, spacing: 0) {
                    boardSection.frame(maxWidth: .infinity)
                    infoSection.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        boardSection
                        infoSection
                    }
                }
            }
        }
        .background(AppColors.surface)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.ink)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .confirmationDialog("Which device is your board?", isPresented: $bluetooth.isPickingDevice, titleVisibility: .visible) {
            ForEach(bluetooth.candidates, id: \.identifier) { peripheral in
                Button(peripheral.name ?? "(unnamed)") {
                    bluetooth.choosePeripheral(peripheral)
                }
            }
            Button("Cancel", role: .cancel) { bluetooth.cancelPicker() }
        }
        .alert("Bluetooth error", isPresented: .constant(bluetooth.lastError != nil)) {
            Button("OK") { bluetooth.lastError = nil }
        } message: {
            Text(bluetooth.lastError ?? "")
        }
        #if os(macOS)
        .frame(minWidth: 950, idealWidth: 1450, maxWidth: 1650)
        #endif
        .task(id: currentClimb.id) {
            betaLinks = (try? await appState.repository.fetchBetaLinks(uuid: currentClimb.uuid, angle: currentClimb.angle)) ?? []
        }
    }

    private var boardSection: some View {
        Group {
            if let board = appState.boardInfo {
                BoardCanvasView(
                    images: board.images,
                    edgeLeft: board.edgeLeft,
                    edgeRight: board.edgeRight,
                    edgeBottom: board.edgeBottom,
                    edgeTop: board.edgeTop,
                    litHolds: litHolds(board: board)
                )
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.surface2)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow
            metaRow

            if let setter = currentClimb.setterUsername {
                Text("Set by \(setter)")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.inkSoft)
            }

            if let description = currentClimb.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.inkSoft)
            }

            illuminateButton
            actionButtons
            betaSection

            if let appURL = appState.boardInfo?.appURL, !appURL.isEmpty {
                Link("Open in board app →", destination: URL(string: "\(appURL)/climbs/\(climb.uuid)")!)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.accent)
            }
        }
        .padding(24)
    }

    private var titleRow: some View {
        HStack {
            Text(currentClimb.name).font(.title2).bold().foregroundStyle(AppColors.ink)
            Spacer()
            Button {
                Task { await appState.toggleFavorite(for: currentClimb) }
            } label: {
                Image(systemName: currentClimb.favorited ? "heart.fill" : "heart")
                    .foregroundStyle(currentClimb.favorited ? AppColors.favorite : AppColors.inkSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 28)
    }

    private var metaRow: some View {
        let errorPrefix = (currentClimb.gradeError ?? 0) > 0 ? "+" : "-"
        let errorSuffix = String(format: "%.2f", abs(currentClimb.gradeError ?? 0)).trimmingLeadingZero()
        var text = "\(currentClimb.grade ?? "?") (\(errorPrefix)\(errorSuffix)) at \(currentClimb.angle)°"
        if currentClimb.isClassic { text += " ©" }
        if currentClimb.sent {
            text += " ✓ Sent" + (currentClimb.sendCount > 1 ? " ×\(currentClimb.sendCount)" : "")
        } else if currentClimb.tries > 0 {
            text += " • Tried \(currentClimb.tries)×"
        }
        return Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.accent)
    }

    @ViewBuilder
    private var betaSection: some View {
        if !betaLinks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Beta")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.inkSoft)
                    .textCase(.uppercase)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(betaLinks) { beta in
                            betaLinkCard(beta)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func betaLinkCard(_ beta: BetaLink) -> some View {
        Link(destination: URL(string: beta.link) ?? URL(string: "https://instagram.com")!) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    if let thumbnail = beta.thumbnail, let url = URL(string: thumbnail) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                AppColors.surface2
                            }
                        }
                    } else {
                        AppColors.surface2
                        Image(systemName: "play.circle.fill").foregroundStyle(AppColors.inkSoft)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if let username = beta.foreignUsername {
                    Text("@\(username)")
                        .font(.caption2)
                        .foregroundStyle(AppColors.inkSoft)
                        .lineLimit(1)
                        .frame(width: 96, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var illuminateButton: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Light up board") {
                guard let board = appState.boardInfo else { return }
                bluetooth.illuminate(
                    frames: currentClimb.frames,
                    placementPositions: board.placementPositions,
                    ledColors: board.ledColors
                )
            }
            .buttonStyle(.bordered)

            if !bluetooth.status.isEmpty {
                Text(bluetooth.status).font(.caption).foregroundStyle(AppColors.inkSoft)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button("+1 Try") {
                Task { await appState.logTry(for: currentClimb) }
            }
            .buttonStyle(.bordered)

            Button(currentClimb.sent ? "Log another send ✓" : "Mark as sent ✓") {
                Task { await appState.logAscent(for: currentClimb) }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.success)
        }
    }

    private func litHolds(board: BoardInfo) -> [Int: Color] {
        var result: [Int: Color] = [:]
        for frame in currentClimb.frames.split(separator: "p") {
            let parts = frame.split(separator: "r")
            guard parts.count == 2, let placementId = Int(parts[0]), let roleId = Int(parts[1]) else { continue }
            guard let hex = board.colors[roleId] else { continue }
            result[placementId] = Color(hex: hex)
        }
        return result
    }
}

private extension String {
    func trimmingLeadingZero() -> String {
        var result = self
        while result.hasPrefix("0") && result.count > 1 && result[result.index(after: result.startIndex)] != "." {
            result.removeFirst()
        }
        return result
    }
}
