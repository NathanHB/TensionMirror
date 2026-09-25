import SwiftUI

struct RestTimerHeaderView: View {
    @EnvironmentObject var restTimer: RestTimer

    private static let lengths = [(120, "2m"), (180, "3m"), (300, "5m")]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Self.lengths, id: \.0) { seconds, label in
                    ChipButton(label: label, isActive: restTimer.duration == seconds) {
                        restTimer.setDuration(seconds)
                    }
                }
            }
            .fixedSize()

            Text(restTimer.formatted)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .frame(minWidth: 40)
                .foregroundStyle(restTimer.isRunning ? AppColors.accent : (restTimer.isDone ? Color(hex: "c0392b") : AppColors.ink))
                .fixedSize()

            Button(restTimer.isRunning ? "Stop" : "Start rest") {
                restTimer.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .lineLimit(1)
            .fixedSize()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
