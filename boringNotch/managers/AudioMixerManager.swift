//
//  AudioMixerManager.swift
//  boringNotch
//

import AppKit
import CoreAudio
import Foundation

struct AppAudioProcess: Identifiable, Equatable {
    let id: AudioObjectID
    let pid: pid_t
    let name: String
    let icon: NSImage?
    var volume: Float32
    var muted: Bool

    static func == (lhs: AppAudioProcess, rhs: AppAudioProcess) -> Bool {
        lhs.id == rhs.id && lhs.volume == rhs.volume && lhs.muted == rhs.muted
    }
}

typealias AppAudioEntry = AppAudioProcess

@MainActor
final class AudioMixerManager: ObservableObject {
    static let shared = AudioMixerManager()

    @Published var processes: [AppAudioProcess] = []

    private var pollTask: Task<Void, Never>?
    private var activeTaps: [pid_t: AudioObjectID] = [:]
    private var volumeStore: [String: Float32] = [:]
    private var muteStore: [String: Bool] = [:]

    private init() {
        refresh()
        startPolling()
        #if DEBUG
        selfCheck()
        #endif
    }

    deinit {
        pollTask?.cancel()
        if #available(macOS 14.2, *) {
            for (_, tapID) in activeTaps {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() {
        processes = enumerateAudioProcesses()
    }

    // MARK: - Process Enumeration
    private func enumerateAudioProcesses() -> [AppAudioProcess] {
        var result: [AppAudioProcess] = []
        let myPID = getpid()
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != myPID
        }

        for app in runningApps {
            let pid = app.processIdentifier
            guard let audioID = getAudioObjectID(for: pid) else { continue }
            let name = app.localizedName ?? "App"
            let key = app.bundleIdentifier ?? "\(pid)"
            let vol = volumeStore[key] ?? 1.0
            let isMuted = muteStore[key] ?? false

            result.append(
                AppAudioProcess(
                    id: audioID,
                    pid: pid,
                    name: name,
                    icon: app.icon,
                    volume: vol,
                    muted: isMuted
                )
            )
        }
        return result
    }

    private func getAudioObjectID(for pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var targetPID = pid
        var objectID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &targetPID,
            &size,
            &objectID
        )
        return (status == noErr && objectID != kAudioObjectUnknown) ? objectID : nil
    }

    // MARK: - CoreAudio Process Tap (macOS 14.2+)
    private func updateProcessTap(for pid: pid_t, audioID: AudioObjectID, muted: Bool) {
        guard #available(macOS 14.2, *) else { return }

        if let existingTap = activeTaps[pid] {
            AudioHardwareDestroyProcessTap(existingTap)
            activeTaps.removeValue(forKey: pid)
        }

        let desc = CATapDescription()
        desc.name = "BoringNotchTap_\(pid)"
        desc.processes = [audioID]
        desc.muteBehavior = muted ? .muted : .unmuted

        var tapID: AudioObjectID = 0
        if AudioHardwareCreateProcessTap(desc, &tapID) == noErr {
            activeTaps[pid] = tapID
        }
    }

    // MARK: - Volume & Mute Controls
    func setVolume(_ volume: Float32, _ app: AppAudioProcess) {
        setVolume(app.id, volume)
    }

    func setVolume(_ objectID: AudioObjectID, _ volume: Float32) {
        let clamped = max(0, min(1, volume))
        if let index = processes.firstIndex(where: { $0.id == objectID }) {
            let pid = processes[index].pid
            let key = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "\(pid)"
            processes[index].volume = clamped
            volumeStore[key] = clamped
            let shouldMute = clamped == 0 || processes[index].muted
            updateProcessTap(for: pid, audioID: objectID, muted: shouldMute)
        }
    }

    func toggleMute(_ app: AppAudioProcess) {
        toggleMute(app.id)
    }

    func toggleMute(_ objectID: AudioObjectID) {
        if let index = processes.firstIndex(where: { $0.id == objectID }) {
            let newMute = !processes[index].muted
            let pid = processes[index].pid
            let key = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "\(pid)"
            processes[index].muted = newMute
            muteStore[key] = newMute
            updateProcessTap(for: pid, audioID: objectID, muted: newMute || processes[index].volume == 0)
        }
    }

    #if DEBUG
    func selfCheck() {
        let list = enumerateAudioProcesses()
        _ = list.count
    }
    #endif
}

// Backward compatibility
typealias PerAppAudioManager = AudioMixerManager
