import SwiftUI

/// Persistent top bar shown above the tabs, matching the web app's
/// `.topbar`: brand on the left, rest timer on the right, visible no
/// matter which tab is active.
struct HeaderBar: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) {
                brand
                Spacer()
                RestTimerHeaderView()
            }

            VStack(alignment: .leading, spacing: 10) {
                brand
                RestTimerHeaderView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AppColors.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColors.border).frame(height: 1)
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tension Mirror").font(.system(size: 20, weight: .bold))
            Text("Board 2 · Mirror layout · 12×12")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.inkSoft)
        }
    }
}
