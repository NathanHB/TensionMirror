import SwiftUI

/// One row per logged send, grouped by calendar day - matches the web
/// app's `.history-day` / `.history-list` / `.history-row`.
struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var entries: [HistoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var grouped: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.loggedAt) }
        return groups.keys.sorted(by: >).map { day in (day, groups[day]!.sorted { $0.loggedAt > $1.loggedAt }) }
    }

    var body: some View {
        ScrollView {
            content
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(AppColors.bg)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if let errorMessage {
            emptyState("Couldn't load history", detail: errorMessage)
        } else if entries.isEmpty {
            emptyState("No sends logged yet", detail: "Use \"Mark as sent\" on a climb to start your history.")
        } else {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(grouped, id: \.day) { group in
                    dayCard(day: group.day, entries: group.entries)
                }
            }
        }
    }

    private func dayCard(day: Date, entries: [HistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sectionTitle(for: day, count: entries.count))
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.inkSoft)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    historyRow(entry)
                    if index < entries.count - 1 {
                        Rectangle().fill(AppColors.border).frame(height: 1)
                    }
                }
            }
            .background(AppColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.loggedAt, style: .time)
                .font(.caption)
                .foregroundStyle(AppColors.inkSoft)
                .frame(width: 64, alignment: .leading)
            Text(entry.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.ink)
            Spacer()
            if let grade = entry.grade {
                Text(grade)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .background(AppColors.accentSoft)
                    .clipShape(Capsule())
            }
            Text("\(entry.angle)°").font(.caption).foregroundStyle(AppColors.inkSoft)
            if entry.isClassic {
                Text("★").font(.caption2).foregroundStyle(AppColors.gold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sectionTitle(for day: Date, count: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return "\(formatter.string(from: day)) · \(count) climb\(count == 1 ? "" : "s")"
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.headline).foregroundStyle(AppColors.inkSoft)
            Text(detail).font(.caption).foregroundStyle(AppColors.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await appState.repository.fetchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
