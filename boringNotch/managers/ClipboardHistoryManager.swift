//
//  ClipboardHistoryManager.swift
//  boringNotch
//

import AppKit
import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let date: Date
    let text: String?
    let imagePath: String?
    let kind: String // "text", "url", "image", "file"

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }

    var thumbnailImage: NSImage? {
        guard let path = imagePath, FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }
}

// For backward compatibility if needed
typealias ClipboardEntry = ClipboardItem

@MainActor
final class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()
    static let maxEntries = 50

    @Published var history: [ClipboardItem] = []
    
    // Alias for legacy references
    var entries: [ClipboardItem] {
        get { history }
        set { history = newValue }
    }

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var pollTask: Task<Void, Never>?

    private var storageURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = appSupport.appendingPathComponent("BoringNotch", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("clipboard_history.json")
    }

    private init() {
        loadHistory()
        startPolling()
        #if DEBUG
        selfCheck()
        #endif
    }

    func startPolling() {
        guard pollTask == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkPasteboard()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let types = pb.types, !types.isEmpty else { return }

        // 1. Check for file URLs
        if let paths = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstURL = paths.first {
            if firstURL.isFileURL {
                enqueue(text: firstURL.path, kind: "file")
                return
            } else {
                enqueue(text: firstURL.absoluteString, kind: "url")
                return
            }
        }

        // 2. Check for web URL string
        if let str = pb.string(forType: .string), let url = URL(string: str), url.scheme != nil && (url.scheme == "http" || url.scheme == "https") {
            enqueue(text: str, kind: "url")
            return
        }

        // 3. Plain text
        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            enqueue(text: text, kind: "text")
            return
        }

        // 4. Image
        if let image = NSImage(pasteboard: pb), let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let tempDir = FileManager.default.temporaryDirectory
            let filePath = tempDir.appendingPathComponent("clip_\(UUID().uuidString).png").path
            if (try? pngData.write(to: URL(fileURLWithPath: filePath))) != nil {
                enqueue(imagePath: filePath, kind: "image")
            }
        }
    }

    private func enqueue(text: String? = nil, imagePath: String? = nil, kind: String, date: Date = Date()) {
        let item = ClipboardItem(date: date, text: text, imagePath: imagePath, kind: kind)
        history.removeAll {
            if let t = item.text, $0.text == t { return true }
            if let ip = item.imagePath, $0.imagePath == ip { return true }
            return false
        }
        history.insert(item, at: 0)
        if history.count > Self.maxEntries {
            history.removeLast(history.count - Self.maxEntries)
        }
        saveHistory()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case "image":
            if let path = item.imagePath, let img = NSImage(contentsOfFile: path) {
                pb.writeObjects([img])
            }
        case "file":
            if let path = item.text {
                pb.writeObjects([URL(fileURLWithPath: path) as NSURL])
            }
        case "url":
            if let urlStr = item.text, let url = URL(string: urlStr) {
                pb.writeObjects([url as NSURL])
            }
        default:
            if let text = item.text {
                pb.setString(text, forType: .string)
            }
        }
        lastChangeCount = pb.changeCount
    }

    // Alias for compatibility
    func copyToPasteboard(_ item: ClipboardItem) {
        copyToClipboard(item)
    }

    func deleteItem(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
        if let path = item.imagePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        saveHistory()
    }

    func clearAll() {
        for item in history {
            if let path = item.imagePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        history.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        guard let url = storageURL else { return }
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Failed to save clipboard history: \(error)")
        }
    }

    private func loadHistory() {
        guard let url = storageURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            history = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            NSLog("Failed to load clipboard history: \(error)")
        }
    }
}

#if DEBUG
extension ClipboardHistoryManager {
    func selfCheck() {
        let original = history
        history = []
        for i in 0..<5 {
            enqueue(text: "item \(i)", kind: "text")
        }
        assert(history.count == 5, "Expected 5 items")
        assert(history.first?.text == "item 4", "Expected most recent first")
        if let item = history.first {
            deleteItem(item)
            assert(history.count == 4, "Expected 4 items after delete")
        }
        clearAll()
        assert(history.isEmpty, "Expected empty history after clearAll")
        history = original
    }
}
#endif
