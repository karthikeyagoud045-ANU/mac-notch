//
//  ShelfPersistenceService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import CloudKit
import Foundation

// Access model types
@_exported import struct Foundation.URL

final class ShelfPersistenceService {
    static let shared = ShelfPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // CloudKit container & sync settings
    private let ckRecordType = "ShelfItemRecord"
    private var isSyncing = false

    var iCloudFileURL: URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let dir = container.appendingPathComponent("Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("items.json")
    }

    static func pickNewerData(_ a: URL, _ b: URL) -> Data? {
        let fm = FileManager.default
        let mtime: (URL) -> Date = { url in
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            return attrs?[.modificationDate] as? Date ?? .distantPast
        }
        guard let da = try? Data(contentsOf: a), let db = try? Data(contentsOf: b) else {
            return (try? Data(contentsOf: a)) ?? (try? Data(contentsOf: b))
        }
        return mtime(a) >= mtime(b) ? da : db
    }

    private func loadLatestData() -> Data? {
        guard let iCloudFileURL else { return try? Data(contentsOf: fileURL) }
        return Self.pickNewerData(fileURL, iCloudFileURL)
    }

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (support ?? fm.temporaryDirectory).appendingPathComponent("boringNotch", isDirectory: true).appendingPathComponent("Shelf", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("items.json")
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        #if DEBUG
        debugVerifyMtimePick()
        #endif
    }

    private func debugVerifyMtimePick() {
        let check = FileManager.default
        let dir = check.temporaryDirectory.appendingPathComponent("ShelfMtimeCheck-\(UUID().uuidString)")
        try? check.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? check.removeItem(at: dir) }

        let oldURL = dir.appendingPathComponent("old.json")
        let newURL = dir.appendingPathComponent("new.json")
        try? Data("{}".utf8).write(to: oldURL)
        try? Data("{}".utf8).write(to: newURL)
        try? check.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: oldURL.path)

        if let picked = Self.pickNewerData(oldURL, newURL) {
            _ = picked.count
        }
    }

    func load() -> [ShelfItem] {
        guard let data = loadLatestData() else { return [] }
        
        if let items = try? decoder.decode([ShelfItem].self, from: data) {
            return items
        }
        
        do {
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                return []
            }
            
            var validItems: [ShelfItem] = []
            for jsonItem in jsonArray {
                if let itemData = try? JSONSerialization.data(withJSONObject: jsonItem),
                   let item = try? decoder.decode(ShelfItem.self, from: itemData) {
                    validItems.append(item)
                }
            }
            return validItems
        } catch {
            return []
        }
    }

    func save(_ items: [ShelfItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
            if let iCloudFileURL {
                try? data.write(to: iCloudFileURL, options: .atomic)
            }
            // Trigger asynchronous CloudKit sync (local-first, graceful degradation)
            syncToCloudKit(items: items)
        } catch {
            NSLog("Failed to save shelf items: \(error)")
        }
    }

    // MARK: - CloudKit Sync Layer
    func syncToCloudKit(items: [ShelfItem]) {
        guard !isSyncing else { return }
        isSyncing = true

        Task.detached(priority: .utility) { [weak self] in
            defer { self?.isSyncing = false }
            guard let self = self else { return }

            let database = CKContainer.default().privateCloudDatabase
            do {
                let data = try self.encoder.encode(items)
                let recordID = CKRecord.ID(recordName: "ShelfGlobalState")
                let record = CKRecord(recordType: self.ckRecordType, recordID: recordID)
                record["payload"] = data
                record["itemCount"] = items.count as NSNumber
                record["updatedAt"] = Date()

                _ = try await database.modifyRecords(saving: [record], deleting: [])
                NSLog("[CloudKit] Shelf state synced successfully")
            } catch {
                NSLog("[CloudKit] Sync gracefully skipped or failed: \(error.localizedDescription)")
            }
        }
    }

    func fetchFromCloudKit() async -> [ShelfItem]? {
        let database = CKContainer.default().privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "ShelfGlobalState")
        do {
            let record = try await database.record(for: recordID)
            guard let data = record["payload"] as? Data else { return nil }
            return try decoder.decode([ShelfItem].self, from: data)
        } catch {
            NSLog("[CloudKit] Fetch skipped or unavailable: \(error.localizedDescription)")
            return nil
        }
    }
}
