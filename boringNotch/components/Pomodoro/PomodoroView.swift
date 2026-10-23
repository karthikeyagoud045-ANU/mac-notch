//
//  PomodoroView.swift
//  boringNotch
//

import SwiftUI

struct PomodoroView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared

    private var phaseDuration: Double {
        switch pomodoro.phase {
        case .idle, .work: return Double(PomodoroManager.workDuration)
        case .breakTime: return Double(PomodoroManager.breakDuration)
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            VStack(spacing: 12) {
                ZStack {
                    CircularProgressView(
                        progress: Double(pomodoro.timeRemaining) / phaseDuration,
                        color: pomodoro.phase == .breakTime ? Color.teal : Color.white
                    )
                    .frame(width: 92, height: 92)

                    Text(pomodoro.displayTime)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Text(phaseLabel)
                    .font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.7))
                    .kerning(1)

                HStack(spacing: 10) {
                    Button {
                        pomodoro.phase == .idle ? pomodoro.startOrResume() : pomodoro.pause()
                    } label: {
                        Image(systemName: pomodoro.phase == .idle ? "play.fill" : "pause.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Capsule().fill(.white.opacity(0.12)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        pomodoro.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Capsule().fill(.white.opacity(0.12)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        pomodoro.pause()
                        pomodoro.reset()
                    } label: {
                        Text("Reset")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Capsule().fill(.white.opacity(0.12)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
        }
        .transition(.opacity)
    }

    private var phaseLabel: String {
        switch pomodoro.phase {
        case .idle: return "Ready"
        case .work: return "Focus"
        case .breakTime: return "Break"
        }
    }
}
