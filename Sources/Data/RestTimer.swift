import Foundation
#if os(macOS)
import AppKit
#else
import AudioToolbox
#endif

/// Global header countdown, independent of whichever tab is active - not
/// scoped to the +1 Game (matches the web app's header rest timer).
@MainActor
final class RestTimer: ObservableObject {
    @Published var duration: Int = 180
    @Published var remaining: Int = 180
    @Published var isRunning = false

    private var timer: Timer?

    var isDone: Bool { remaining == 0 && !isRunning }

    var formatted: String {
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    func setDuration(_ seconds: Int) {
        duration = seconds
        stop()
        remaining = seconds
    }

    func toggle() {
        if isRunning {
            stop()
            remaining = duration
        } else {
            start()
        }
    }

    private func start() {
        stop()
        remaining = duration
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            remaining = 0
            stop()
            playBeep()
        }
    }

    private func playBeep() {
        #if os(macOS)
        NSSound.beep()
        #else
        AudioServicesPlaySystemSound(1005)
        #endif
    }
}
