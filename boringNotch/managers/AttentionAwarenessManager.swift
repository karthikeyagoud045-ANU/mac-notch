//
//  AttentionAwarenessManager.swift
//  boringNotch
//

import AppKit
import AVFoundation
import Foundation
import Vision

@MainActor
final class AttentionAwarenessManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = AttentionAwarenessManager()

    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    @Published var isUserPresent: Bool = true
    @Published var lastFaceDetectedTime: Date = Date()

    // 2-minute absence threshold as requested
    static let absenceThreshold: TimeInterval = 120

    private var lastAnalysisTime: Date = .distantPast
    private var checkTimerTask: Task<Void, Never>?
    private override init() {
        super.init()
        #if DEBUG
        selfCheck()
        #endif
    }

    // MARK: - Permissions
    var hasCameraPermission: Bool {
        WebcamManager.shared.authorizationStatus == .authorized || AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    func requestCameraPermission() {
        WebcamManager.shared.checkAndRequestVideoAuthorization()
    }

    func startMonitoring() {
        if WebcamManager.shared.authorizationStatus == .notDetermined {
            WebcamManager.shared.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard WebcamManager.shared.authorizationStatus == .authorized else {
            requestCameraPermission()
            return
        }
        lastFaceDetectedTime = Date()
        isUserPresent = true
        WebcamManager.shared.sampleBufferDelegate = self
        WebcamManager.shared.startSession()

        // Periodic absence check task
        checkTimerTask?.cancel()
        checkTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self = self, self.isEnabled else { break }
                let elapsed = Date().timeIntervalSince(self.lastFaceDetectedTime)
                if elapsed >= Self.absenceThreshold && self.isUserPresent {
                    self.isUserPresent = false
                    self.triggerDisplaySleep()
                }
            }
        }
    }

    func stopMonitoring() {
        checkTimerTask?.cancel()
        checkTimerTask = nil
        if WebcamManager.shared.sampleBufferDelegate === self {
            WebcamManager.shared.sampleBufferDelegate = nil
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        Task { @MainActor in
            let now = Date()
            guard now.timeIntervalSince(AttentionAwarenessManager.shared.lastAnalysisTime) >= 2.0 else { return }
            AttentionAwarenessManager.shared.lastAnalysisTime = now

            let request = VNDetectFaceRectanglesRequest { req, err in
                guard err == nil else { return }
                let faceCount = (req.results as? [VNFaceObservation])?.count ?? 0
                Task { @MainActor in
                    if faceCount > 0 {
                        AttentionAwarenessManager.shared.lastFaceDetectedTime = Date()
                        AttentionAwarenessManager.shared.isUserPresent = true
                    }
                }
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Display Sleep Action
    func triggerDisplaySleep() {
        NSLog("[AttentionAwareness] User absent for 2 minutes. Triggering display sleep.")
        CGDisplaySleep()
    }

    #if DEBUG
    func selfCheck() {
        assert(Self.absenceThreshold == 120, "Absence threshold must be 2 minutes")
    }
    #endif
}

/// Helper function to put displays to sleep safely on macOS
func CGDisplaySleep() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["displaysleepnow"]
    try? process.run()
}
