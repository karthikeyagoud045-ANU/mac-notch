import Foundation

// ponytail: minimal pomodoro — work/break loop, no settings UI until asked
@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()
    private init() {}

    enum Phase: String {
        case idle, work, breakTime
    }

    static let workDuration: TimeInterval = 25 * 60
    static let breakDuration: TimeInterval = 5 * 60

    @Published var phase: Phase = .idle
    @Published var timeRemaining: TimeInterval = workDuration

    private var countdownTask: Task<Void, Never>?

    func startOrResume() {
        if phase == .idle {
            phase = .work
            timeRemaining = Self.workDuration
        }
        guard countdownTask == nil else { return }
        countdownTask = Task { [weak self] in
            while let self = self, self.phase != .idle {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                guard self.tick() else { break }
            }
            self?.endLoop()
        }
    }

    @discardableResult
    private func tick() -> Bool {
        timeRemaining -= 1
        guard timeRemaining > 0 else {
            phase = (phase == .work) ? .breakTime : .work
            timeRemaining = phase == .work ? Self.workDuration : Self.breakDuration
            return true
        }
        return true
    }

    private func endLoop() {
        countdownTask = nil
    }

    func pause() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    func reset() {
        pause()
        phase = .idle
        timeRemaining = Self.workDuration
    }

    var displayTime: String {
        let m = Int(timeRemaining) / 60
        let s = Int(timeRemaining) % 60
        return String(format: "%d:%02d", m, s)
    }
}

#if DEBUG
extension PomodoroManager {
    static func selfCheck() {
        let m = PomodoroManager.shared
        assert(m.phase == .idle && m.timeRemaining == Self.workDuration)
        m.startOrResume()
        assert(m.phase == .work)
        m.timeRemaining = 1
        let carried = m.tick()
        assert(carried && m.phase == .breakTime && m.timeRemaining == Self.breakDuration)
        assert(m.displayTime == "5:00")
        m.tick()
        assert(m.phase == .work)
        m.reset()
        assert(m.phase == .idle)
    }
}
#endif
