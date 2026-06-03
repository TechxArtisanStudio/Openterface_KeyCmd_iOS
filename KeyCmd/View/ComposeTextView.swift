import SwiftUI

struct SavedTextItem: Identifiable, Hashable {
    let id: UUID
    let text: String
    let createdAt: Date
    var title: String    // First 10 chars of text by default
    var pinned: Bool

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), title: String? = nil, pinned: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.title = title ?? String(text.prefix(10))
        self.pinned = pinned
    }
}

// MARK: - Codable for SavedTextItem (with migration for old items)
extension SavedTextItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, title, pinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? String(text.prefix(10))
        self.pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(title, forKey: .title)
        try c.encode(pinned, forKey: .pinned)
    }
}

private class SavedTextStore: ObservableObject {
    static let shared = SavedTextStore()
    private let key = "compose_saved_texts"

    @Published var items: [SavedTextItem] = []
    /// Remembers the original index for unpin restore. Only one index per item.
    private var unpinIndex: [UUID: Int] = [:]

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedTextItem].self, from: data)
        else { items = []; return }
        items = decoded
    }

    func save(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item = SavedTextItem(text: text)
        items.insert(item, at: 0)
        persist()
    }

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        // Also clean unpinIndex entries
        unpinIndex = unpinIndex.filter { item in items.contains(where: { $0.id == item.key }) }
        persist()
    }

    func pinToTop(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        if item.pinned {
            // Unpin: restore to remembered index
            let restoreIdx = unpinIndex[id] ?? items.count
            let restored = SavedTextItem(id: item.id, text: item.text, createdAt: item.createdAt, title: item.title, pinned: false)
            items.insert(restored, at: min(restoreIdx, items.count))
        } else {
            // Pin: remember current index, then move to top
            unpinIndex[item.id] = idx
            items.insert(SavedTextItem(id: item.id, text: item.text, createdAt: item.createdAt, title: item.title, pinned: true), at: 0)
            reorderPinned()
        }
        persist()
    }

    func rename(_ id: UUID, newTitle: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx] = SavedTextItem(id: items[idx].id, text: items[idx].text, createdAt: items[idx].createdAt, title: newTitle, pinned: items[idx].pinned)
        persist()
    }

    /// Reorder pinned items at the top, then by createdAt desc.
    private func reorderPinned() {
        // Only reorder pinned section; unpin keeps its position.
        var pinned: [SavedTextItem] = []
        var unpinned: [SavedTextItem] = []
        for item in items {
            if item.pinned { pinned.append(item) } else { unpinned.append(item) }
        }
        pinned.sort { $0.createdAt > $1.createdAt }
        items = pinned + unpinned
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - DeferredTextView
/// Custom UITextView that prevents the ~3 s keyboard prediction XPC from
/// blocking the gesture pipeline.
///
/// Root cause: the first time any UITextView in the app receives
/// `reloadInputViews()` after switching from a dummy `inputView` to the
/// real system keyboard (nil inputView), UIKit makes a synchronous XPC call
/// to the keyboard prediction daemon. On iPad this call fails with "Operation
/// not authorized" but only after ~3 s of retry — all on the main thread.
///
/// Fix: swizzle `reloadInputViews()` so it runs on the next run loop cycle
/// instead of synchronously. The gesture pipeline has already returned by
/// then, so the 3 s delay does not block touch handling.
class DeferredTextView: UITextView {
    static let swizzleToken: () = {
        let originalSel = #selector(UIView.reloadInputViews)
        let swizzledSel = #selector(DeferredTextView.swizzled_reloadInputViews)
        guard let originalMethod = class_getInstanceMethod(DeferredTextView.self, originalSel),
              let swizzledMethod = class_getInstanceMethod(DeferredTextView.self, swizzledSel)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc private func swizzled_reloadInputViews() {
        // Intercept every reloadInputViews() call and defer it to the next
        // run loop so the gesture pipeline is not blocked by the XPC delay.
        DispatchQueue.main.async { [weak self] in
            self?.swizzled_reloadInputViews()  // calls original impl
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        _ = DeferredTextView.swizzleToken
        super.init(frame: frame, textContainer: textContainer)
    }

    required init?(coder: NSCoder) {
        _ = DeferredTextView.swizzleToken
        super.init(coder: coder)
    }
}

// MARK: - PlainTextEditor
/// UIViewRepresentable wrapper that prevents the 3-5 s "System gesture gate
/// timed out" freeze. Root cause: `becomeFirstResponder()` on a standard
/// UITextView makes SYNCHRONOUS XPC calls to the iOS keyboard prediction
/// service; on this device the service returns "Operation not authorized"
/// and iOS waits 3 s for a timeout — blocking the main thread inside the
/// gesture pipeline.
///
/// Fix strategy: use a dummy zero-height inputView so that
/// becomeFirstResponder() completes immediately (no keyboard XPC init).
/// Then swap to the real keyboard from textViewDidBeginEditing on the next
/// run loop — the XPC still takes ~3 s but runs outside the gesture pipeline.
private struct PlainTextEditor: UIViewRepresentable {
    @Binding var text: String
    var isDisabled: Bool = false
    var highlightNonAscii: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> DeferredTextView {
        // Ensure swizzle is active before creating any text view.
        _ = DeferredTextView.swizzleToken
        let tv = DeferredTextView(frame: .zero, textContainer: nil)
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 14)
        tv.backgroundColor = .clear
        // Disable every prediction / autocorrect subsystem.
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.smartInsertDeleteType = .no
        // Disables iOS 17+ inline type-ahead prediction XPC calls.
        if #available(iOS 17.0, *) { tv.inlinePredictionType = .no }
        // Suppress autofill lookups (contacts, passwords, etc.).
        tv.textContentType = UITextContentType(rawValue: "")
        // Remove QuickType / assistant bar buttons.
        tv.inputAssistantItem.leadingBarButtonGroups = []
        tv.inputAssistantItem.trailingBarButtonGroups = []
        return tv
    }

    func updateUIView(_ tv: DeferredTextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text {
            tv.text = text
            // Re-apply highlights after text change
            if highlightNonAscii { context.coordinator.applyNonAsciiHighlight(to: tv) }
        }
        tv.isEditable = !isDisabled
        tv.isSelectable = true
        if highlightNonAscii {
            context.coordinator.applyNonAsciiHighlight(to: tv)
        } else if context.coordinator.hasHighlights {
            context.coordinator.clearHighlights(tv: tv, preserveText: tv.text)
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlainTextEditor
        var hasHighlights = false
        private var savedSelectedRange: NSRange = NSRange(location: NSNotFound, length: 0)

        init(_ parent: PlainTextEditor) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Swap from dummy inputView to real keyboard.
            // reloadInputViews() is swizzled to run on the next run loop,
            // so the XPC delay doesn't block the gesture pipeline.
            if textView.inputView != nil {
                textView.inputView = nil
                textView.reloadInputViews()
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // Restore dummy inputView for next fast focus.
            if textView.inputView == nil {
                textView.inputView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            // User typed — clear highlights immediately
            if hasHighlights {
                hasHighlights = false
                clearHighlights(tv: textView, preserveText: textView.text)
            }
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            savedSelectedRange = textView.selectedRange
        }

        func applyNonAsciiHighlight(to tv: UITextView) {
            let plain = tv.text as NSString
            guard plain.length > 0 else { return }
            let mutable = NSMutableAttributedString(string: tv.text, attributes: [
                .font: tv.font ?? .systemFont(ofSize: 14),
                .foregroundColor: UIColor.label
            ])
            // First pass: find non-ASCII scalars
            var found = false
            var ranges: [NSRange] = []
            plain.enumerateSubstrings(in: NSRange(location: 0, length: plain.length), options: .byComposedCharacterSequences) { substr, range, _, _ in
                let s = substr ?? ""
                if s.unicodeScalars.contains(where: { $0.value > 127 }) {
                    ranges.append(range)
                    found = true
                }
            }
            guard found else { return }

            // Apply yellow background to non-ASCII ranges
            for range in ranges {
                mutable.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), range: range)
            }

            let cursor = savedSelectedRange.location != NSNotFound ? savedSelectedRange : NSRange(location: plain.length, length: 0)
            tv.attributedText = mutable
            tv.selectedRange = cursor
            hasHighlights = true
        }

        func clearHighlights(tv: UITextView, preserveText: String) {
            let cursor = tv.selectedRange
            tv.attributedText = NSAttributedString(string: preserveText, attributes: [
                .font: tv.font ?? .systemFont(ofSize: 14),
                .foregroundColor: UIColor.label
            ])
            tv.selectedRange = cursor
            hasHighlights = false
        }
    }
}

struct ComposeTextView: View {
    @ObservedObject var keyboardManager: KeyboardManager

    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var profileMgr = ShortcutProfileManager.shared
    @ObservedObject private var prefs = KmProPrefs.shared
    @ObservedObject private var store: SavedTextStore = SavedTextStore.shared

    @State private var text: String = ""
    @State private var sending = false
    @State private var undoSnapshot: String = ""
    @State private var undoClearEligible = false
    @State private var fixedRowsLocalFnLocked = false
    @State private var cachedText: String = UserDefaults.standard.string(forKey: "compose_cached_text") ?? ""

    @State private var keyboardHeight: CGFloat = 0
    @State private var warningInfo: ComposeSendGate.WarningInfo?
    @State private var showWarningSheet = false
    @State private var showAsciiPreview = false
    @State private var pendingSendText: String = ""
    @State private var highlightNonAscii = false
    @State private var sendCancelledToast = false
    @State private var unicodeMode = false
    @State private var showUnicodeConfirm = false
    @State private var renameTarget: SavedTextItem?
    @State private var renameText: String = ""
    @State private var selectedItem: SavedTextItem?
    @State private var showLibraryPreview = false
    @State private var libraryPreviewText = ""
    @State private var showLibrarySheet = false

    // MARK: - Shortcut strip data

    private var shortcutPages: [ShortcutPage] {
        let pm = aiSettings.targetOS == .macOS ? "Cmd" : "Ctrl"
        let combo: ([String], String) -> Void = { keyboardManager.handleKeyCombo(modifiers: $0, key: $1) }
        let source = profileEntries()
        guard !source.isEmpty else { return [standardShortcuts(combo, pm)] }
        let chunks = stride(from: 0, to: source.count, by: 7).map { Array(source[$0..<min($0 + 7, source.count)]) }
        let name = profileMgr.activeProfile?.name ?? ""
        return chunks.enumerated().map { (i, c) in ShortcutPage(title: c.count > 1 ? "\(name) \(i + 1)/\(c.count)" : name, entries: c) }
    }

    // MARK: - Fixed rows pages

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
        let p0Fkeys: [ShortcutEntry] = [
            ("F1","1"),("F2","2"),("F3","3"),("F4","4"),("F5","5"),("F6","6"),
        ].map { Self.keyEntry(km, label: $0.0, icon: "", badge: $0.1) }
        let p0FnKeys: [ShortcutEntry] = [
            ("F7","7"),("F8","8"),("F9","9"),("F10","0"),("F11","+"),("F12","-"),
        ].map { Self.keyEntry(km, label: $0.0, icon: "", badge: $0.1) }
        let p0 = FixedRowsPage(
            row1: lock ? ["7","8","9","0","+","-","*"].map { te($0) } : p0FnKeys + [te("#")],
            row2: lock ? ["1","2","3","4","5","6"].map { te($0) } + [tog] : p0Fkeys + [tog]
        )

        // Page 1 — Modifiers + Navigation
        let isMacOS = aiSettings.targetOS == .macOS
        let isWindows = aiSettings.targetOS == .windows
        let modCfg: [(String, String, String)] = isMacOS
            ? [("Ctrl", "", "control"), ("Alt", "", "option"), ("Cmd", "", "command")]
            : isWindows ? [("Ctrl", "CTRL", ""), ("Alt", "ALT", ""), ("Cmd", "WIN", "")]
                        : [("Ctrl", "CTRL", ""), ("Alt", "ALT", ""), ("Cmd", "SUP", "")]
        let modEntries = modCfg.map { cfg in ShortcutEntry(label: cfg.1, icon: cfg.2.isEmpty ? nil : cfg.2, isActive: keyboardManager.activeModifiers.contains(cfg.0)) { km.handleModifierToggle(cfg.0) } }
        let imeIndicator = ShortcutEntry(label: "IME", icon: nil, isActive: true) {}
        let p1Locked = FixedRowsPage(
            row1: [keKey("SCR","Scroll Lock"),keKey("PRT","PrtSc"),keKey("CAPS","Caps"),keKey("PAUSE","Pause"),keKey("HOME","Home"),keKey("PGUP","PgUp"),imeIndicator],
            row2: [keKey("SPACE","Space"),keKey("BKSP","Backspace"),keKey("DEL","Delete"),keKey("INS","Insert"),keKey("END","End"),keKey("PGDN","PgDn"),tog]
        )
        let p1Unlocked = FixedRowsPage(
            row1: modEntries + [keKey("TAB","Tab"),keKey("UP","Up"),keKey("ENTER","Enter"),imeIndicator],
            row2: [keKey("ESC","Escape"),Self.modifierEntry(km,label:"SHIFT",icon:"shift",key:"Shift"),keKey("DEL","Delete"),keKey("LEFT","Left"),keKey("DOWN","Down"),keKey("RIGHT","Right"),tog]
        )

        // Page 2 — Punctuation
        // unlock row1: ( ) [ ] : # @  → badge shows lock mode: ` ~ ' " % ^ |
        // unlock row2: / \ | ? - _     → badge shows lock mode: < > * & , .
        let p2Row1: [(String, String)] = [
            ("(","`"),(")","~"),("[","'"),("]","\""),(":",":"),("#","#"),("@","@"),
        ]
        let p2Row2: [(String, String)] = [
            ("/","<"),("\\",">"),("|","*"),("?","&"),("-","/"),("_","."),
        ]
        let p2 = FixedRowsPage(
            row1: lock ? ["`","~","'","\"","%","^","|"].map { te($0) }
                       : p2Row1.map { Self.textEntryWithBadge(km, label: $0.0, badge: $0.1) },
            row2: lock ? ["<",">","*","&",",","."].map { te($0) } + [tog]
                       : p2Row2.map { Self.textEntryWithBadge(km, label: $0.0, badge: $0.1) } + [tog]
        )

        return [p0, lock ? p1Locked : p1Unlocked, p2]
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
    private static func keyEntry(_ km: KeyboardManager, label: String, icon: String, key: String? = nil, badge: String? = nil) -> ShortcutEntry {
        let k = key ?? label
        var entry = ShortcutEntry(label: label, icon: icon.isEmpty ? nil : icon) { km.handleKeyPress(k) }
        entry.badge = badge
        return entry
    }
    private static func textEntry(_ km: KeyboardManager, label: String) -> ShortcutEntry {
        ShortcutEntry(label: label, icon: nil) { km.handleTextInput(label) }
    }
    private static func textEntryWithBadge(_ km: KeyboardManager, label: String, badge: String?) -> ShortcutEntry {
        var entry = Self.textEntry(km, label: label)
        entry.badge = badge
        return entry
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Main content
            NavigationView {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Type or paste your text here, edit as needed then tap Send.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .padding(18)
                                .allowsHitTesting(false)
                        }
                        PlainTextEditor(text: $text, isDisabled: sending, highlightNonAscii: highlightNonAscii)
                            .padding(8)
                            .background(Color(UIColor.systemBackground))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(UIColor.separator), lineWidth: 1))
                            .frame(minHeight: 220)
                            .onChange(of: text) { newValue in
                                if !newValue.isEmpty && undoClearEligible {
                                    undoClearEligible = false
                                    undoSnapshot = ""
                                }
                                // Cache text for recovery when navigating away
                                if prefs.composeDraftRetentionEnabled {
                                    UserDefaults.standard.set(newValue, forKey: "compose_cached_text")
                                }
                                // Reset highlight when user enters new text
                                if highlightNonAscii {
                                    highlightNonAscii = false
                                }
                            }
                    }
                    .padding(12)

                    // Action buttons bar
                    HStack(spacing: 8) {
                        actionBtn(icon: "xmark", color: !text.isEmpty ? .red : .secondary, enabled: !text.isEmpty) {
                            undoSnapshot = ""; undoClearEligible = false; text = ""
                            if prefs.composeDraftRetentionEnabled {
                                UserDefaults.standard.removeObject(forKey: "compose_cached_text")
                            }
                        }
                        actionBtn(icon: "arrow.uturn.backward", color: undoClearEligible && !undoSnapshot.isEmpty ? .orange : .secondary, enabled: undoClearEligible && !undoSnapshot.isEmpty) {
                            text = undoSnapshot; undoSnapshot = ""; undoClearEligible = false
                        }
                        actionBtn(icon: "externaldrive.fill.badge.plus", color: .secondary) {
                            store.save(text)
                        }
                        actionBtn(icon: "bookmark.fill", color: .secondary) {
                            showLibrarySheet = true
                        }
                        Spacer()
                        let btnDisabled = !canSend
                        Button(action: { onSendTapped() }) {
                            Image(systemName: sending || keyboardManager.isSending ? "stop.fill" : "paperplane.fill")
                                .font(.system(size: 16))
                                .foregroundColor(btnDisabled ? .secondary : .blue)
                                .padding(.vertical, 8).padding(.horizontal, 16)
                                .background(Color(UIColor.tertiarySystemBackground)).cornerRadius(8)
                        }
                        .disabled(btnDisabled)
                        .onReceive(keyboardManager.$isSending) { newVal in
                            if !newVal && sending {
                                sending = false
                                text = ""
                                if prefs.composeDraftRetentionEnabled {
                                    UserDefaults.standard.removeObject(forKey: "compose_cached_text")
                                }
                            }
                        }
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
            }
            .sheet(isPresented: $showWarningSheet) {
                sendWarningAlert
            }
            .sheet(isPresented: $showAsciiPreview) {
                asciiPreviewSheet
            }
            .alert("Confirm Unicode Send", isPresented: $showUnicodeConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Send Anyway", role: .destructive) {
                    executeSend()
                }
            } message: {
                Text(unicodeConfirmMessage)
            }
            .sheet(isPresented: $showLibrarySheet) {
                savedTextLibrarySheet
            }
        }
        .onAppear {
            // Restore cached text if the editor is empty (only when draft retention is enabled)
            if prefs.composeDraftRetentionEnabled && text.isEmpty && !cachedText.isEmpty {
                text = cachedText
            }
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
            // Ensure text is cached before leaving (only when draft retention is enabled)
            if prefs.composeDraftRetentionEnabled && !text.isEmpty {
                UserDefaults.standard.set(text, forKey: "compose_cached_text")
            }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        }
        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight : 0)
    }

    // MARK: - Send gate

    private var isConnected: Bool { !keyboardManager.bleManager.connectedDevices.isEmpty }
    private var canSend: Bool {
        if sending || keyboardManager.isSending { return false }
        return isConnected && !text.isEmpty
    }

    /// Warning message shown in Unicode send confirmation.
    private var unicodeConfirmMessage: String {
        let hint: String
        switch aiSettings.targetOS {
        case .macOS:
            hint = "The target Mac must have the \"Unicode Hex Input\" input source enabled (System Settings → Keyboard → Input Sources → + → English → Unicode Hex Input). Holding Option key during send to type hex digits."
        case .windows:
            hint = "The target Windows PC must support Alt + Numpad + hex digit Unicode entry. Ensure the numeric keypad is available."
        case .linux:
            hint = "The target Linux host must support Ctrl+Shift+U followed by hex digits for Unicode entry. Ensure the focused application accepts this shortcut."
        }
        return "If the target device does not have the correct Unicode input method active, the keystrokes may be interpreted as regular shortcuts, causing unexpected behavior (e.g., opening apps, closing windows).\n\n\(hint)"
    }

    private func onSendTapped() {
        if sending || keyboardManager.isSending {
            keyboardManager.cancelSend()
            return
        }

        let assessment = ComposeSendGate.assess(isConnected: isConnected, text: text)

        switch assessment.hardBlock {
        case .noConnection:
            HapticFeedbackManager.shared.triggerButtonPress()
            return
        case .emptyText:
            return
        case nil:
            break
        }

        if let warning = assessment.warningInfo {
            warningInfo = warning
            pendingSendText = text
            unicodeMode = false
            showWarningSheet = true
            return
        }

        executeSend()
    }

    private func executeSend() {
        HapticFeedbackManager.shared.triggerButtonPress()
        sending = true
        let sendText = pendingSendText.isEmpty ? text : pendingSendText
        keyboardManager.handleTextInput(sendText)
        pendingSendText = ""
    }

    /// Send only ASCII characters, dropping non-ASCII (used by "Send Anyway" in warning dialog).
    private func executeSendAsciiOnly() {
        HapticFeedbackManager.shared.triggerButtonPress()
        sending = true
        let fullText = pendingSendText.isEmpty ? text : pendingSendText
        let asciiText = fullText.unicodeScalars.filter { $0.value <= 127 }.map { String($0) }.joined()
        keyboardManager.handleTextInput(asciiText)
        pendingSendText = ""
    }

    // MARK: - Alerts

    private var sendWarningAlert: some View {
        Group {
            if let info = warningInfo {
                ComposeSendWarningAlert(
                    text: pendingSendText,
                    warningInfo: info,
                    unicodeMode: $unicodeMode,
                    onSendAnyway: { showWarningSheet = false; executeSendAsciiOnly() },
                    onSendUnicode: { showWarningSheet = false; showUnicodeConfirm = true },
                    onCheck: { showWarningSheet = false; highlightNonAscii = true },
                    onPreview: { showWarningSheet = false; showAsciiPreview = true }
                )
            }
        }
    }

    private var asciiPreviewSheet: some View {
        let preview = ComposeSendGate.asciiPreview(of: pendingSendText)
        return AnyView(
            NavigationView {
                ScrollView {
                    Text(preview.isEmpty ? "(All characters are non-ASCII)" : preview)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle("ASCII Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Close") { showAsciiPreview = false } } }
            }
            .id(pendingSendText)
        )
    }

    // MARK: - Saved Texts Library Sheet

    private var savedTextLibrarySheet: some View {
        NavigationView {
            List {
                ForEach(itemsSorted()) { item in
                    SavedTextRow(item: item, isSelected: selectedItem?.id == item.id) { item in
                        withAnimation { selectedItem = item }
                    } onDelete: { id in
                        if selectedItem?.id == id { selectedItem = nil }
                        if let idx = store.items.firstIndex(where: { $0.id == id }) {
                            store.delete(at: IndexSet([idx]))
                        }
                    } onRename: { item in
                        renameTarget = item
                        renameText = item.title
                    } onPin: { id in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.pinToTop(id)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Saved Texts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { showLibrarySheet = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let item = selectedItem {
                        HStack(spacing: 12) {
                            Button {
                                libraryPreviewText = item.text
                                showLibraryPreview = true
                            } label: {
                                Image(systemName: "eye")
                            }
                            Button { loadItem(item) } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Button { sendItem(item) } label: {
                                Image(systemName: "paperplane")
                            }
                        }
                    }
                }
            }
            .onAppear { selectedItem = nil }
            .sheet(isPresented: $showLibraryPreview) {
                let preview = ComposeSendGate.asciiPreview(of: libraryPreviewText)
                NavigationView {
                    ScrollView {
                        Text(preview.isEmpty ? "(All characters are non-ASCII)" : preview)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                    }
                    .navigationTitle("ASCII Preview")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Close") { showLibraryPreview = false } } }
                }
                .id(libraryPreviewText)
            }
            .alert("Rename", isPresented: .constant(renameTarget != nil)) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") {
                    if let target = renameTarget, !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        store.rename(target.id, newTitle: renameText)
                    }
                    renameTarget = nil
                }
            }
        }
    }

    private func previewItem(_ item: SavedTextItem) {
        pendingSendText = item.text
        showAsciiPreview = true
    }

    private func loadItem(_ item: SavedTextItem) {
        text = item.text
        if prefs.composeDraftRetentionEnabled {
            UserDefaults.standard.set(item.text, forKey: "compose_cached_text")
        }
        showLibrarySheet = false
    }

    private func sendItem(_ item: SavedTextItem) {
        showLibrarySheet = false
        let assessment = ComposeSendGate.assess(
            isConnected: isConnected,
            text: item.text
        )
        if assessment.hardBlock != nil { return }
        if let warning = assessment.warningInfo {
            warningInfo = warning
            pendingSendText = item.text
            unicodeMode = false
            showWarningSheet = true
        } else {
            pendingSendText = item.text
            executeSend()
        }
    }

    private func itemsSorted() -> [SavedTextItem] {
        var items = store.items
        items.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.createdAt > b.createdAt
        }
        return items
    }

    private func actionBtn(icon: String, color: Color, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(enabled ? color : Color.secondary.opacity(0.3))
                .padding(10).background(Color(UIColor.tertiarySystemBackground)).cornerRadius(8)
        }
        .disabled(!enabled)
    }
}

// MARK: - SavedTextRow

/// Extracted row view so SwiftUI caches each cell and avoids first-swipe stutter.
struct SavedTextRow: View {
    let item: SavedTextItem
    let isSelected: Bool
    let onSelect: (SavedTextItem) -> Void
    let onDelete: (UUID) -> Void
    let onRename: (SavedTextItem) -> Void
    let onPin: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if item.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundColor(.orange)
                }
                Text(item.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(item.createdAt, style: .date).font(.caption2).foregroundColor(.secondary)
            }
            Text(bodyPreview).font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        .onTapGesture { onSelect(item) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDelete(item.id) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { onRename(item) } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
            Button { onPin(item.id) } label: {
                Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
    }

    private var bodyPreview: String {
        let titlePrefix = String(item.text.prefix(item.title.count))
        if item.title == titlePrefix {
            return String(item.text.dropFirst(min(item.title.count, item.text.count)))
        }
        return item.text
    }
}
