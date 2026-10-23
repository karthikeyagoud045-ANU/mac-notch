//
//  ScreenSnipManager.swift
//  boringNotch
//

import AppKit
import Carbon.HIToolbox
import Foundation
import ScreenCaptureKit
import Vision

@MainActor
final class ScreenSnipManager: NSObject, ObservableObject {
    static let shared = ScreenSnipManager()

    @Published var isSnipping: Bool = false
    private var overlayWindow: SnipOverlayWindow?

    override init() {
        super.init()
        #if DEBUG
        Self.selfCheck()
        #endif
    }

    // MARK: - Permission Check
    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - HotKey Registration (Cmd+Shift+S)
    private static let hotKeySignature: OSType = 0x534E4950 // 'SNIP'
    private var hotKeyRef: EventHotKeyRef?

    func registerHotKey() {
        guard hotKeyRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        InstallEventHandler(GetApplicationEventTarget()!, Self.eventHandlerUPP, 1, &eventType, nil, nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget()!, 0, &hotKeyRef)
    }

    func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private static let eventHandlerUPP: EventHandlerUPP = { _, _, _ in
        Task { @MainActor in
            ScreenSnipManager.shared.startSnip()
        }
        return noErr
    }

    func startSnip() {
        guard !isSnipping else { return }
        guard hasScreenRecordingPermission() else {
            requestScreenRecordingPermission()
            return
        }
        guard let screen = NSScreen.main else { return }
        isSnipping = true

        let overlay = SnipOverlayWindow(screen: screen)
        self.overlayWindow = overlay
        overlay.onComplete = { [weak self] cgRect, displayID in
            Task { @MainActor in
                self?.isSnipping = false
                self?.overlayWindow = nil
                await self?.captureAndRecognize(rect: cgRect, displayID: displayID)
            }
        }
        overlay.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func captureAndRecognize(rect: CGRect, displayID: CGDirectDisplayID) async {
        guard rect.width > 2 && rect.height > 2 else { return }

        var capturedImage: CGImage?

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first {
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.sourceRect = rect
                config.width = max(1, Int(rect.width * 2))
                config.height = max(1, Int(rect.height * 2))
                config.showsCursor = false
                capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            }
        } catch {
            NSLog("ScreenCaptureKit error: \(error)")
        }

        guard let image = capturedImage else {
            NSLog("ScreenSnip: capture failed or permission denied")
            return
        }

        // Run OCR via Vision
        Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                let text = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                guard !text.isEmpty else { return }

                await MainActor.run {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    NotificationCenter.default.post(
                        name: Notification.Name("ScreenSnipDidComplete"),
                        object: text
                    )
                }
            } catch {
                NSLog("ScreenSnip: OCR recognition error: \(error)")
            }
        }
    }

    static func cocoaToCGRect(_ windowRect: NSRect, in screenFrame: NSRect) -> CGRect {
        CGRect(
            x: windowRect.minX,
            y: screenFrame.maxY - windowRect.maxY,
            width: windowRect.width,
            height: windowRect.height
        )
    }

    #if DEBUG
    static func selfCheck() {
        let f = cocoaToCGRect(
            NSRect(x: 10, y: 20, width: 30, height: 40),
            in: NSRect(x: 0, y: 0, width: 100, height: 120)
        )
        assert(f.origin.x == 10 && f.origin.y == 60 && f.width == 30 && f.height == 40, "Cocoa to CoreGraphics coordinate transform incorrect")
    }
    #endif
}

// Backward compatibility alias
typealias SnipManager = ScreenSnipManager

private final class SnipOverlayWindow: NSWindow {
    var onComplete: ((CGRect, CGDirectDisplayID) -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        level = .mainMenu + 2
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SnipOverlayView(frame: screen.frame)
        contentView = view
        makeFirstResponder(view)
        view.onComplete = { [weak self] rect, screen in
            guard let self else { return }
            let windowRect = view.convert(rect, to: nil)
            let cgRect = ScreenSnipManager.cocoaToCGRect(self.convertToScreen(windowRect), in: screen.frame)
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
            self.onComplete?(cgRect, displayID)
        }
    }
}

private final class SnipOverlayView: NSView {
    private var selectionStart: NSPoint?
    private var selectionRect: NSRect?
    var onComplete: ((NSRect, NSScreen) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        selectionStart = convert(event.locationInWindow, from: nil)
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = selectionStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        selectionRect = NSRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(start.x - point.x),
            height: abs(start.y - point.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = selectionRect, let screen = window?.screen else { return }
        if rect.width < 5 || rect.height < 5 {
            selectionRect = nil
            needsDisplay = true
            return
        }
        onComplete?(rect, screen)
        window?.orderOut(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape cancels
            window?.orderOut(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        guard let rect = selectionRect, let ctx = NSGraphicsContext.current else { return }
        let cg = ctx.cgContext
        cg.setBlendMode(.clear)
        ctx.shouldAntialias = false
        rect.fill()
        cg.setBlendMode(.normal)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.5
        border.stroke()
    }
}
