import SwiftUI

struct SavedTextItem: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let createdAt: Date
}

private class SavedTextStore: ObservableObject {
    static let shared = SavedTextStore()
    private let key = "compose_saved_texts"

    @Published var items: [SavedTextItem] = []

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedTextItem].self, from: data)
        else { items = []; return }
        items = decoded
    }

    func save(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item = SavedTextItem(id: UUID(), text: text, createdAt: Date())
        items.insert(item, at: 0)
        persist()
    }

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct ComposeTextView: View {
    @ObservedObject var keyboardManager: KeyboardManager

    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var profileMgr = ShortcutProfileManager.shared

    private let store = SavedTextStore.shared

    @State private var text: String = ""
    @State private var sending = false
    @State private var showLibrary = false
    @State private var undoSnapshot: String = ""
    @State private var undoClearEligible = false
    @State private var fixedRowsLocalFnLocked = false

    @State private var keyboardHeight: CGFloat = 0

    // MARK: - Shortcut data (mirrors ProKeyboardMouseView)

    private var shortcutPages: [ShortcutPage] {
        let pm = aiSettings.targetOS == .macOS ? "Cmd" : "Ctrl"
        let combo: ([String], String) -> Void = { keyboardManager.handleKeyCombo(modifiers: $0, key: $1) }
        let source = profileEntries()
        guard !source.isEmpty else { return [standardShortcuts(combo, pm)] }
        let chunks = stride(from: 0, to: source.count, by: 7).map { Array(source[$0..<min($0 + 7, source.count)]) }
        let name = profileMgr.activeProfile?.name ?? ""
        return chunks.enumerated().map { (i, c) in ShortcutPage(title: c.count > 1 ? "\(name) \(i + 1)/\(c.count)" : name, entries: c) }
    }

    private func profileEntries() -> [ShortcutEntry] {
        guard let active = profileMgr.activeProfile else { return [] }
        let items = !profileMgr.myShortcuts(for: active.id).isEmpty ? profileMgr.myShortcuts(for: active.id) : Array(active.categories.first?.shortcuts.prefix(7) ?? [])
        return items.map { item in
            let mods = (item.modifier ?? "").split(separator: "+").map(String.init)
            return ShortcutEntry(label: String(item.description.prefix(8)), icon: nil) {
                mods.isEmpty ? keyboardManager.handleSpecialKey(item.keyCode) : keyboardManager.handleKeyCombo(modifiers: mods, key: item.keyCode)
            }
        }
    }

    private func standardShortcuts(_ combo: @escaping ([String], String) -> Void, _ pm: String) -> ShortcutPage {
        ShortcutPage(title: "Standard", entries: [
            ShortcutEntry(label: "ALL",   icon: "text.badge.checkmark") { combo([pm], "A") },
            ShortcutEntry(label: "COPY",  icon: "doc.on.doc")           { combo([pm], "C") },
            ShortcutEntry(label: "CUT",   icon: "scissors")             { combo([pm], "X") },
            ShortcutEntry(label: "PASTE", icon: "clipboard")            { combo([pm], "V") },
            ShortcutEntry(label: "SAVE",  icon: "externaldrive")        { combo([pm], "S") },
            ShortcutEntry(label: "UNDO",  icon: "arrow.uturn.backward") { combo([pm], "Z") },
            ShortcutEntry(label: "FIND",  icon: "magnifyingglass")      { combo(["Ctrl"], "F") },
        ])
    }

    private var fixedRowsPages: [FixedRowsPage] {
        let km = keyboardManager
        let lock = fixedRowsLocalFnLocked
        let te = { Self.textEntry(km, label: $0) }
        let ke = { Self.keyEntry(km, label: $0, icon: "") }
        let keKey = { (label: String, key: String) in Self.keyEntry(km, label: label, icon: "", key: key) }
        let tog = fixedRowsToggleEntry

        // Page 0 — F-keys / number-symbol
        let p0 = FixedRowsPage(
            row1: lock ? ["7","8","9","0","+","-","*"].map { te($0) }
                       : ["F7","F8","F9","F10","F11","F12"].map { ke($0) } + [te("#")],
            row2: lock ? ["1","2","3","4","5","6"].map { te($0) } + [tog]
                       : ["F1","F2","F3","F4","F5","F6"].map { ke($0) } + [tog]
        )

        // Page 1 — Modifiers + Navigation
        let isMacOS = aiSettings.targetOS == .macOS
        let isWindows = aiSettings.targetOS == .windows
        let modCfg: [(String, String, String)] = isMacOS
            ? [("Ctrl", "", "control"), ("Alt", "", "option"), ("Cmd", "", "command")]
            : isWindows ? [("Ctrl", "CTRL", ""), ("Alt", "ALT", ""), ("Cmd", "", "logo.windows")]
                        : [("Ctrl", "CTRL", ""), ("Alt", "ALT", ""), ("Cmd", "SUP", "")]
        let modEntries = modCfg.map { cfg in ShortcutEntry(label: cfg.1, icon: cfg.2.isEmpty ? nil : cfg.2, isActive: keyboardManager.activeModifiers.contains(cfg.0)) { km.handleModifierToggle(cfg.0) } }
        let p1 = FixedRowsPage(
            row1: modEntries + [keKey("TAB", "Tab"), keKey("UP", "Up"), keKey("ENTER", "Enter")],
            row2: [keKey("ESC", "Escape"), Self.modifierEntry(km, label: "SHIFT", icon: "shift", key: "Shift"), keKey("DEL", "Delete"), keKey("LEFT", "Left"), keKey("DOWN", "Down"), keKey("RIGHT", "Right")]
        )

        // Page 2 — Punctuation
        let p2 = FixedRowsPage(
            row1: (lock ? ["`","~","'","\"","%","^","|"] : ["(",")","[","]",":","#","@"]).map { te($0) },
            row2: (lock ? ["<",">","*","&",",","."] : ["/","\\","|","?","-","_"]).map { te($0) } + [tog]
        )

        return [p0, p1, p2]
    }

    private var fixedRowsToggleEntry: ShortcutEntry {
        ShortcutEntry(label: "", icon: "arrow.left.arrow.right", isActive: fixedRowsLocalFnLocked) {
            withAnimation(.easeInOut(duration: 0.15)) { fixedRowsLocalFnLocked.toggle() }
        }
    }

    private static func modifierEntry(_ km: KeyboardManager, label: String, icon: String, key: String? = nil) -> ShortcutEntry {
        let k = key ?? label
        return ShortcutEntry(label: label, icon: icon, isActive: km.activeModifiers.contains(k)) { km.handleModifierToggle(k) }
    }
    private static func keyEntry(_ km: KeyboardManager, label: String, icon: String, key: String? = nil) -> ShortcutEntry {
        let k = key ?? label
        return ShortcutEntry(label: label, icon: icon.isEmpty ? nil : icon) { km.handleKeyPress(k) }
    }
    private static func textEntry(_ km: KeyboardManager, label: String) -> ShortcutEntry {
        ShortcutEntry(label: label, icon: nil) { km.handleTextInput(label) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Type here and tap Send to deliver to the connected device")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(18)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .padding(8)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(UIColor.separator), lineWidth: 1))
                    .disabled(sending)
                    .frame(minHeight: 220)
                    .onChange(of: text) { newValue in
                        if !newValue.isEmpty && undoClearEligible {
                            undoClearEligible = false
                            undoSnapshot = ""
                        }
                    }
            }
            .padding(12)

            // Action buttons bar
            HStack(spacing: 8) {
                actionBtn(icon: "eraser", color: undoClearEligible ? .orange : .secondary) {
                    if undoClearEligible && !undoSnapshot.isEmpty {
                        text = undoSnapshot; undoSnapshot = ""; undoClearEligible = false
                    } else if !text.isEmpty {
                        undoSnapshot = text; undoClearEligible = true; text = ""
                    }
                }
                actionBtn(icon: "externaldrive.fill.badge.plus", color: .secondary) {
                    store.save(text)
                }
                actionBtn(icon: "bookmark.fill", color: .secondary) {
                    showLibrary = true
                }
                Spacer()
                Button(action: {
                    guard !sending, !text.isEmpty else { return }
                    sending = true
                    HapticFeedbackManager.shared.triggerButtonPress()
                    keyboardManager.handleTextInput(text)
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                        DispatchQueue.main.async { sending = false; text = "" }
                    }
                }) {
                    Image(systemName: sending ? "stop.fill" : "paperplane.fill")
                        .font(.system(size: 16))
                        .foregroundColor(text.isEmpty ? .secondary : .blue)
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        .background(Color(UIColor.tertiarySystemBackground)).cornerRadius(8)
                }
                .disabled(text.isEmpty || sending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))

            // Shortcut panel
            VStack(spacing: 0) {
                ShortcutStripPager(pages: shortcutPages).id(profileMgr.activeProfileId).padding(.horizontal, 4)
                FixedRowsPager(pages: fixedRowsPages, defaultPageIndex: 1).padding(.horizontal, 4)
            }
            .background(Color(UIColor.secondarySystemBackground))
            .padding(.bottom, 10)
        }
        .sheet(isPresented: $showLibrary) {
            savedTextLibrary
        }
        .onAppear {
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { n in
                if let kf = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.easeOut(duration: 0.3)) {
                        keyboardHeight = kf.height
                    }
                }
            }
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    keyboardHeight = 0
                }
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        }
        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight : 0)
    }

    private var savedTextLibrary: some View {
        NavigationView {
            List {
                ForEach(store.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text).font(.body).lineLimit(3)
                        Text(item.createdAt, style: .date).font(.caption2).foregroundColor(.secondary)
                    }
                    .onTapGesture {
                        text = item.text; showLibrary = false
                    }
                }
                .onDelete { store.delete(at: $0) }
            }
            .navigationTitle("Saved Texts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { showLibrary = false } } }
        }
    }

    private func actionBtn(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(color)
                .padding(10).background(Color(UIColor.tertiarySystemBackground)).cornerRadius(8)
        }
    }
}
