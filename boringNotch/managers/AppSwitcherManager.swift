//
//  AppSwitcherManager.swift
//  boringNotch
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

struct AppSwitcherItem: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let windowCount: Int

    static func == (lhs: AppSwitcherItem, rhs: AppSwitcherItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class AppSwitcherManager: ObservableObject {
    static let shared = AppSwitcherManager()

    @Published var isVisible: Bool = false
    @Published var runningApps: [AppSwitcherItem] = []
    @Published var selectedIndex: Int = 0

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isIntercepting: Bool = false

    private init() {
        refreshApps()
        #if DEBUG
        selfCheck()
        #endif
    }

    // MARK: - Permissions
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        Task { @MainActor in
            _ = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
        }
    }

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    // MARK: - App Enumeration & Window Counting
    func refreshApps() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid()
        }

        // Count on-screen windows per PID using CGWindowListCopyWindowInfo
        var windowCounts: [pid_t: Int] = [:]
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for win in windowList {
                if let pid = win[kCGWindowOwnerPID as String] as? pid_t,
                   let layer = win[kCGWindowLayer as String] as? Int, layer == 0 {
                    windowCounts[pid, default: 0] += 1
                }
            }
        }

        runningApps = apps.map { app in
            AppSwitcherItem(
                id: app.processIdentifier,
                name: app.localizedName ?? "App",
                bundleIdentifier: app.bundleIdentifier,
                icon: app.icon,
                windowCount: windowCounts[app.processIdentifier] ?? 0
            )
        }

        if selectedIndex >= runningApps.count {
            selectedIndex = max(0, runningApps.count - 1)
        }
    }

    // MARK: - Navigation & Activation
    func selectNext() {
        guard !runningApps.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % runningApps.count
    }

    func selectPrevious() {
        guard !runningApps.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + runningApps.count) % runningApps.count
    }

    func activateSelected() {
        guard selectedIndex >= 0 && selectedIndex < runningApps.count else {
            isVisible = false
            return
        }
        let target = runningApps[selectedIndex]
        if let app = NSRunningApplication(processIdentifier: target.id) {
            app.activate()
        }
        isVisible = false
    }

    func dismiss() {
        isVisible = false
    }

    // MARK: - Event Tap Interception (Cmd+Tab)
    func startIntercepting() {
        guard eventTap == nil else { return }

        Task { @MainActor in
            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            guard granted || AXIsProcessTrusted() else {
                NSLog("[AppSwitcherManager] Accessibility authorization needed for Cmd+Tab event tap")
                return
            }
            self.createEventTap()
        }
    }

    private func createEventTap() {
        guard eventTap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let unmanagedSelf = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let manager = Unmanaged<AppSwitcherManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handleEvent(type: type, cgEvent: cgEvent)
            },
            userInfo: unmanagedSelf
        )

        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            isIntercepting = true
        } else {
            NSLog("[AppSwitcherManager] Failed to create CGEventTap")
        }
    }

    func stopIntercepting() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        isIntercepting = false
    }

    private func handleEvent(type: CGEventType, cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = cgEvent.flags
        let isCommandPressed = flags.contains(.maskCommand)
        let isShiftPressed = flags.contains(.maskShift)
        let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyDown {
            // Tab key is keyCode 48 (kVK_Tab)
            if keyCode == 48 && isCommandPressed {
                Task { @MainActor in
                    if !self.isVisible {
                        self.refreshApps()
                        self.selectedIndex = 0
                        self.isVisible = true
                    }
                    if isShiftPressed {
                        self.selectPrevious()
                    } else {
                        self.selectNext()
                    }
                }
                // Suppress system Cmd+Tab
                return nil
            }
        } else if type == .flagsChanged {
            // If Command key is released while visual switcher is active, activate selection
            if !isCommandPressed && isVisible {
                Task { @MainActor in
                    self.activateSelected()
                }
            }
        }

        return Unmanaged.passRetained(cgEvent)
    }

    #if DEBUG
    func selfCheck() {
        refreshApps()
        assert(selectedIndex >= 0, "Selected index should be non-negative")
    }
    #endif
}
