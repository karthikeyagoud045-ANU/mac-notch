//
//  PremiumFeaturesSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PremiumFeaturesSettingsView: View {
    @Default(.enableSystemStats) var enableSystemStats
    @Default(.enablePomodoro) var enablePomodoro
    @Default(.enableClipboardHistory) var enableClipboardHistory
    @Default(.enableAudioMixer) var enableAudioMixer
    @Default(.enableQuickSnip) var enableQuickSnip
    @Default(.enableAttentionAwareness) var enableAttentionAwareness
    @Default(.enableShelfSync) var enableShelfSync
    @Default(.enableAppSwitcher) var enableAppSwitcher

    @ObservedObject var attentionManager = AttentionAwarenessManager.shared
    @ObservedObject var snipManager = ScreenSnipManager.shared
    @ObservedObject var switcherManager = AppSwitcherManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue, .teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("Premium Features")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }

                    Text("Supercharge your notch with powerful utilities, hardware controls, and productivity tools.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)

                // Feature Cards
                VStack(spacing: 12) {
                    featureCard(
                        title: "System Stats HUD",
                        description: "Live CPU and memory load indicators in the notch header bar.",
                        icon: "cpu",
                        iconColor: .orange,
                        isOn: $enableSystemStats
                    )

                    featureCard(
                        title: "Pomodoro Focus Timer",
                        description: "25/5 min focus timer with circular progress ring and one-tap controls.",
                        icon: "timer",
                        iconColor: .teal,
                        isOn: $enablePomodoro
                    )

                    featureCard(
                        title: "Universal Clipboard History",
                        description: "Searchable history of text, URLs, and images with instant pasteboard recall.",
                        icon: "clipboard",
                        iconColor: .blue,
                        isOn: $enableClipboardHistory
                    )

                    featureCard(
                        title: "Per-App Audio Mixer",
                        description: "Real-time CoreAudio process taps with per-app volume sliders and mute toggles.",
                        icon: "slider.horizontal.3",
                        iconColor: .pink,
                        isOn: $enableAudioMixer
                    )

                    featureCard(
                        title: "Quick Snip & OCR",
                        description: "ScreenCaptureKit region selection with instant Vision text recognition.",
                        icon: "crop",
                        iconColor: .yellow,
                        isOn: $enableQuickSnip,
                        permissionAction: !snipManager.hasScreenRecordingPermission() ? {
                            snipManager.requestScreenRecordingPermission()
                        } : nil,
                        permissionLabel: !snipManager.hasScreenRecordingPermission() ? "Grant Screen Access" : nil
                    )

                    featureCard(
                        title: "Attention Awareness",
                        description: "Monitors user presence via webcam and puts display to sleep after 2 minutes away.",
                        icon: "person.badge.shield.checkmark",
                        iconColor: .green,
                        isOn: $enableAttentionAwareness,
                        permissionAction: !attentionManager.hasCameraPermission ? {
                            attentionManager.requestCameraPermission()
                        } : nil,
                        permissionLabel: !attentionManager.hasCameraPermission ? "Grant Camera Access" : nil
                    )

                    featureCard(
                        title: "Shelf iCloud Sync",
                        description: "CloudKit and ubiquitous container synchronization for shelf files, text, and links.",
                        icon: "icloud.fill",
                        iconColor: .cyan,
                        isOn: $enableShelfSync
                    )

                    featureCard(
                        title: "Visual App Switcher",
                        description: "Full-fidelity Cmd+Tab replacement with window count badges and smooth animations.",
                        icon: "macwindow.on.rectangle",
                        iconColor: .purple,
                        isOn: $enableAppSwitcher,
                        permissionAction: !switcherManager.hasAccessibilityPermission ? {
                            switcherManager.requestAccessibilityPermission()
                        } : nil,
                        permissionLabel: !switcherManager.hasAccessibilityPermission ? "Grant Accessibility" : nil
                    )
                }
            }
            .padding(24)
        }
        .background(Color.black.opacity(0.85))
    }

    @ViewBuilder
    private func featureCard(
        title: String,
        description: String,
        icon: String,
        iconColor: Color,
        isOn: Binding<Bool>,
        permissionAction: (() -> Void)? = nil,
        permissionLabel: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconColor.opacity(0.18))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            }

            if let action = permissionAction, let label = permissionLabel {
                Divider().background(Color.white.opacity(0.1))
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                    Text("Permission required to activate this feature.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: action) {
                        Text(label)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.18), in: Capsule())
                            .foregroundColor(.yellow)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
