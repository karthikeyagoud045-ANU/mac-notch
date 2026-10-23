//
//  MixerView.swift
//  boringNotch
//

import SwiftUI

struct MixerView: View {
    @ObservedObject var manager = AudioMixerManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if manager.processes.isEmpty {
                VStack(spacing: 12) {
                    EmptyStateView(message: "No audio-emitting apps found")
                    Button(action: { manager.refresh() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Scan Again")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(manager.processes) { app in
                            HStack(spacing: 10) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 22, height: 22)
                                        .cornerRadius(4)
                                } else {
                                    Image(systemName: "app.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22, height: 22)
                                }

                                Text(app.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: 100, alignment: .leading)

                                Spacer()

                                Button(action: {
                                    manager.toggleMute(app)
                                }) {
                                    Image(systemName: app.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(app.muted ? .red : .white.opacity(0.8))
                                        .frame(width: 26, height: 26)
                                        .background(Color.white.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(.plain)

                                Slider(value: Binding(
                                    get: { Double(app.volume) },
                                    set: { manager.setVolume(Float($0), app) }
                                ), in: 0...1)
                                .frame(width: 100)
                                .tint(.white)
                                .disabled(app.muted)

                                Text("\(Int(app.volume * 100))%")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(app.muted ? Color.secondary : Color.white)
                                    .frame(width: 34, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
