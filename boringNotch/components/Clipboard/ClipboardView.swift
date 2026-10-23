//
//  ClipboardView.swift
//  boringNotch
//

import SwiftUI

struct ClipboardView: View {
    @ObservedObject var manager = ClipboardHistoryManager.shared
    @State private var searchText: String = ""
    @State private var copiedItemId: UUID?

    private var filteredItems: [ClipboardItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return manager.history
        } else {
            return manager.history.filter { item in
                item.text?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))

                TextField("Search clipboard...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.top, 4)

            if filteredItems.isEmpty {
                Spacer()
                EmptyStateView(message: searchText.isEmpty ? "Nothing copied yet" : "No matching items")
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredItems) { item in
                            row(item)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(
                                    copiedItemId == item.id
                                    ? Color.green.opacity(0.2)
                                    : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    manager.copyToClipboard(item)
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        copiedItemId = item.id
                                    }
                                    Task {
                                        try? await Task.sleep(for: .seconds(1))
                                        if copiedItemId == item.id {
                                            copiedItemId = nil
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                }

                // Footer Bar
                HStack {
                    Text("\(filteredItems.count) of \(manager.history.count) items")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        withAnimation(.smooth(duration: 0.25)) {
                            manager.clearAll()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Clear All")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: ClipboardItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: item))
                .foregroundColor(iconColor(for: item))
                .font(.system(size: 14))
                .frame(width: 20)

            if item.kind == "image", let img = item.thumbnailImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 38)
                    .cornerRadius(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(preview(for: item))
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(item.date, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)

            Button(action: {
                withAnimation(.smooth(duration: 0.2)) {
                    manager.deleteItem(item)
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
    }

    private func icon(for item: ClipboardItem) -> String {
        switch item.kind {
        case "image": return "photo"
        case "file": return "doc"
        case "url": return "link"
        default: return "doc.text"
        }
    }

    private func iconColor(for item: ClipboardItem) -> Color {
        switch item.kind {
        case "image": return .purple
        case "file": return .orange
        case "url": return .blue
        default: return .secondary
        }
    }

    private func preview(for item: ClipboardItem) -> String {
        guard let text = item.text, !text.isEmpty else { return "(empty)" }
        return item.kind == "file" ? (text as NSString).lastPathComponent : text
    }
}
