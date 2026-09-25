import SwiftUI

/// Grid card matching the web app's `.climb-card` - green tint once sent,
/// gold border while it's a live project (tried but not sent).
struct ClimbCardView: View {
    let climb: Climb
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    private var errorText: String {
        guard let error = climb.gradeError else { return "" }
        let prefix = error > 0 ? "+" : "-"
        var suffix = String(format: "%.2f", abs(error))
        while suffix.hasPrefix("0") && suffix.count > 1 && suffix[suffix.index(after: suffix.startIndex)] != "." {
            suffix.removeFirst()
        }
        return "\(prefix)\(suffix)"
    }

    private var borderColor: Color {
        if climb.sent { return AppColors.sentBorder }
        if climb.tries > 0 { return AppColors.projectBorder }
        return AppColors.border
    }

    private var background: Color {
        climb.sent ? AppColors.successSoft : AppColors.surface
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(climb.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColors.ink)
                        .lineLimit(2)
                    Spacer()
                    badges
                }
                HStack(spacing: 6) {
                    gradePill
                    Text("(\(errorText)) at \(climb.angle)°")
                        .font(.caption)
                        .foregroundStyle(AppColors.inkSoft)
                }
                HStack(spacing: 12) {
                    Text("★ \(climb.qualityAverage.map { String(format: "%.2f", $0) } ?? "–")")
                    Text("\(climb.ascensionistCount) ascents")
                }
                .font(.caption2)
                .foregroundStyle(AppColors.inkSoft)
                Text("by \(climb.setterUsername ?? "unknown")")
                    .font(.caption2)
                    .foregroundStyle(AppColors.inkSoft)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var badges: some View {
        HStack(spacing: 6) {
            if climb.sent {
                Text(climb.sendCount > 1 ? "✓ \(climb.sendCount)" : "✓")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(AppColors.success)
                    .clipShape(Capsule())
            } else if climb.tries > 0 {
                Text("Tried \(climb.tries)×")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.triesText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AppColors.triesBg)
                    .clipShape(Capsule())
            }
            if climb.isClassic {
                Text("★").foregroundStyle(AppColors.gold)
            }
            Button(action: onToggleFavorite) {
                Image(systemName: climb.favorited ? "heart.fill" : "heart")
                    .foregroundStyle(climb.favorited ? AppColors.favorite : AppColors.inkSoft)
                    .font(.system(size: 14))
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var gradePill: some View {
        Text(climb.grade ?? "?")
            .font(.caption.weight(.bold))
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(AppColors.accentSoft)
            .clipShape(Capsule())
    }
}
