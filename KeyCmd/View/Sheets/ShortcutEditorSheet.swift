import SwiftUI

// MARK: - ShortcutEditorContext

struct ShortcutEditorContext: Identifiable {
    enum Source { case myShortcuts, category }
    let id: String
    let profileId: String
    let categoryId: String?
    let existing: ShortcutItem?
    let source: Source

    init(profileId: String, categoryId: String?, existing: ShortcutItem?, source: Source) {
        self.id         = UUID().uuidString
        self.profileId  = profileId
        self.categoryId = categoryId
        self.existing   = existing
        self.source     = source
    }
}

// MARK: - ShortcutEditorSheet

struct ShortcutEditorSheet: View {
    let context: ShortcutEditorContext
    let onSave: (ShortcutItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var descriptionText: String
    @State private var selectedKeyCode: String?
    @State private var modCmd:   Bool
    @State private var modCtrl:  Bool
    @State private var modShift: Bool
    @State private var modAlt:   Bool

    init(context: ShortcutEditorContext, onSave: @escaping (ShortcutItem) -> Void) {
        self.context = context
        self.onSave  = onSave
        let e = context.existing
        let mods = (e?.modifier ?? "").components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        _descriptionText = State(initialValue: e?.description ?? "")
        _selectedKeyCode = State(initialValue: e?.keyCode)
        _modCmd   = State(initialValue: mods.contains("Cmd"))
        _modCtrl  = State(initialValue: mods.contains("Ctrl"))
        _modShift = State(initialValue: mods.contains("Shift"))
        _modAlt   = State(initialValue: mods.contains("Alt"))
    }

    // MARK: - Key catalog

    private struct KeyEntry: Identifiable {
        let id: String  // keyCode
        let label: String
    }

    private static let letterKeys: [KeyEntry] = (65...90).map { code in
        let c = String(UnicodeScalar(code)!)
        return KeyEntry(id: c, label: c)
    }

    private static let specialKeys: [KeyEntry] = [
        KeyEntry(id: "Escape",    label: "Esc"),
        KeyEntry(id: "Tab",       label: "Tab"),
        KeyEntry(id: "Enter",     label: "Enter"),
        KeyEntry(id: "Space",     label: "Space"),
        KeyEntry(id: "Backspace", label: "Bksp"),
        KeyEntry(id: "Delete",    label: "Del"),
        KeyEntry(id: "Left",      label: "←"),
        KeyEntry(id: "Right",     label: "→"),
        KeyEntry(id: "Up",        label: "↑"),
        KeyEntry(id: "Down",      label: "↓"),
        KeyEntry(id: "Home",      label: "Home"),
        KeyEntry(id: "End",       label: "End"),
        KeyEntry(id: "PgUp",      label: "PgUp"),
        KeyEntry(id: "PgDn",      label: "PgDn"),
        KeyEntry(id: "Insert",    label: "Ins"),
        KeyEntry(id: "F1",  label: "F1"),  KeyEntry(id: "F2",  label: "F2"),
        KeyEntry(id: "F3",  label: "F3"),  KeyEntry(id: "F4",  label: "F4"),
        KeyEntry(id: "F5",  label: "F5"),  KeyEntry(id: "F6",  label: "F6"),
        KeyEntry(id: "F7",  label: "F7"),  KeyEntry(id: "F8",  label: "F8"),
        KeyEntry(id: "F9",  label: "F9"),  KeyEntry(id: "F10", label: "F10"),
        KeyEntry(id: "F11", label: "F11"), KeyEntry(id: "F12", label: "F12"),
    ]

    // MARK: - Derived

    private var modifierString: String? {
        let m = [(modCmd,"Cmd"),(modCtrl,"Ctrl"),(modShift,"Shift"),(modAlt,"Alt")]
            .compactMap { $0.0 ? $0.1 : nil }
        return m.isEmpty ? nil : m.joined(separator: "+")
    }

    private var previewLabel: String {
        guard let key = selectedKeyCode else { return "—" }
        let syms = [(modCmd,"⌘"),(modCtrl,"⌃"),(modShift,"⇧"),(modAlt,"⌥")]
            .compactMap { $0.0 ? $0.1 : nil }
        let keyLabel = Self.letterKeys.first { $0.id == key }?.label
            ?? Self.specialKeys.first { $0.id == key }?.label ?? key
        return (syms + [keyLabel]).joined(separator: " ")
    }

    private var canSave: Bool {
        selectedKeyCode != nil &&
        !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            Form {
                Section("Name") {
                    TextField("e.g. Save, Undo, Open Find…", text: $descriptionText)
                        .autocorrectionDisabled()
                }

                Section("Modifiers") {
                    HStack(spacing: 8) {
                        modButton("⌘ Cmd",  isOn: $modCmd)
                        modButton("⌃ Ctrl", isOn: $modCtrl)
                        modButton("⇧ Shift", isOn: $modShift)
                        modButton("⌥ Alt",  isOn: $modAlt)
                    }
                    .frame(maxWidth: .infinity)
                }

                Section("Keys — Letters") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8),
                        spacing: 6
                    ) {
                        ForEach(Self.letterKeys) { entry in keyChip(entry: entry) }
                    }
                    .padding(.vertical, 4)
                }

                Section("Keys — Special") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5),
                        spacing: 6
                    ) {
                        ForEach(Self.specialKeys) { entry in keyChip(entry: entry) }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Text(previewLabel)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundColor(canSave ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                } header: {
                    Text("Preview")
                } footer: {
                    if selectedKeyCode == nil {
                        Text("Select a key above.").font(.caption).foregroundColor(.secondary)
                    } else if descriptionText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Enter a name.").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(context.existing != nil ? "Edit Shortcut" : "New Shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let keyCode = selectedKeyCode else { return }
                        let desc = descriptionText.trimmingCharacters(in: .whitespaces)
                        let keyLabel = Self.letterKeys.first { $0.id == keyCode }?.label
                            ?? Self.specialKeys.first { $0.id == keyCode }?.label
                            ?? keyCode
                        let item = ShortcutItem(
                            id: context.existing?.id ?? UUID().uuidString,
                            description: desc,
                            key: keyLabel,
                            modifier: modifierString,
                            keyCode: keyCode
                        )
                        onSave(item)
                    }
                    .disabled(!canSave)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sub-views

    private func modButton(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(isOn.wrappedValue ? Color.accentColor : Color.gray.opacity(0.18))
                .foregroundColor(isOn.wrappedValue ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func keyChip(entry: KeyEntry) -> some View {
        let isSelected = selectedKeyCode == entry.id
        return Button {
            selectedKeyCode = isSelected ? nil : entry.id
        } label: {
            Text(entry.label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.18))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
