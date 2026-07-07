//
//  FavoritesEditorSheet.swift
//  KeyCmd
//
//  Long-press favorites editor — Android MyShortcutsReorderBottomSheet parity.
//  Presented from shortcut strip keys via .contextMenu "Edit Favorites".
//

import SwiftUI

struct FavoritesEditorSheet: View {
    let keyboardManager: KeyboardManager

    @ObservedObject private var profileManager = ShortcutProfileManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .favorites
    @State private var myShortcuts: [ShortcutItem] = []
    @State private var browseCategoryId: String?
    @State private var editorContext: ShortcutEditorContext?

    enum Tab: String, CaseIterable, Identifiable {
        case favorites = "Favorites"
        case browse = "Browse"
        var id: String { rawValue }
    }

    private var activeProfile: ShortcutProfileData? { profileManager.activeProfile }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Divider().padding(.top, 8)

                if selectedTab == .favorites {
                    favoritesTab
                } else {
                    browseTab
                }
            }
            .navigationTitle("Edit Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
            .sheet(item: $editorContext) { ctx in
                ShortcutEditorSheet(context: ctx) { saved in
                    handleEditorSave(saved, context: ctx)
                    editorContext = nil
                }
            }
            .onAppear { loadMyShortcuts() }
        }
    }

    // MARK: - Favorites tab

    private var favoritesTab: some View {
        Group {
            if myShortcuts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.square.on.square")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No favorites yet")
                        .font(.headline)
                    Text("Switch to Browse tab to add shortcuts from categories.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(myShortcuts) { shortcut in
                        ShortcutListRow(
                            shortcut: shortcut,
                            trailingIcon: "trash",
                            trailingColor: .red,
                            trailingAction: { myShortcuts.removeAll { $0 == shortcut } },
                            onTap: { executeShortcut(shortcut) }
                        )
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button { editorContext = makeEditorContext(shortcut) } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onMove { myShortcuts.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { myShortcuts.remove(atOffsets: $0) }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    // MARK: - Browse tab

    private var browseTab: some View {
        VStack(spacing: 0) {
            if let cats = activeProfile?.categories, !cats.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cats) { cat in
                            Button { browseCategoryId = cat.id } label: {
                                Text(cat.name)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(browseCategoryId == cat.id ? Color.accentColor : Color.gray.opacity(0.18))
                                    .foregroundColor(browseCategoryId == cat.id ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Color(UIColor.secondarySystemBackground))

                Divider()

                if let catId = browseCategoryId,
                   let cat = activeProfile?.categories.first(where: { $0.id == catId }) {
                    browseList(category: cat)
                } else if let first = activeProfile?.categories.first {
                    // Defer category selection until first render
                    Color.clear.onAppear { browseCategoryId = first.id }
                }
            } else {
                Text("No categories available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func browseList(category: ShortcutCategoryData) -> some View {
        List {
            ForEach(category.shortcuts) { shortcut in
                let bookmarked = myShortcuts.contains(shortcut)
                ShortcutListRow(
                    shortcut: shortcut,
                    trailingIcon: bookmarked ? "bookmark.fill" : "bookmark",
                    trailingColor: bookmarked ? .accentColor : .secondary,
                    trailingAction: {
                        if bookmarked { myShortcuts.removeAll { $0 == shortcut } }
                        else { myShortcuts.append(shortcut) }
                    },
                    onTap: { executeShortcut(shortcut) }
                )
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Persistence

    private func loadMyShortcuts() {
        guard let profile = activeProfile else { return }
        myShortcuts = profileManager.myShortcuts(for: profile.id)
        if browseCategoryId == nil { browseCategoryId = profile.categories.first?.id }
    }

    private func save() {
        guard let profile = activeProfile else { return }
        profileManager.updateMyShortcuts(for: profile.id, items: myShortcuts)
    }

    // MARK: - Editor

    private func makeEditorContext(_ shortcut: ShortcutItem) -> ShortcutEditorContext {
        ShortcutEditorContext(
            profileId: activeProfile?.id ?? "",
            categoryId: nil,
            existing: shortcut,
            source: .myShortcuts
        )
    }

    private func handleEditorSave(_ item: ShortcutItem, context: ShortcutEditorContext) {
        if context.existing != nil {
            myShortcuts = myShortcuts.map { $0.id == item.id ? item : $0 }
        } else if !myShortcuts.contains(item) {
            myShortcuts.append(item)
        }
    }

    // MARK: - Execute

    private func executeShortcut(_ shortcut: ShortcutItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let modifier = shortcut.modifier, !modifier.isEmpty {
            let mods = modifier.components(separatedBy: "+")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            keyboardManager.handleKeyCombo(modifiers: mods, key: shortcut.keyCode)
            return
        }
        if shortcut.keyCode.contains("+") {
            let parts = shortcut.keyCode.components(separatedBy: "+")
            if parts.count >= 2, let key = parts.last {
                keyboardManager.handleKeyCombo(modifiers: Array(parts.dropLast()), key: key)
                return
            }
        }
        keyboardManager.handleKeyPress(shortcut.keyCode)
    }
}
