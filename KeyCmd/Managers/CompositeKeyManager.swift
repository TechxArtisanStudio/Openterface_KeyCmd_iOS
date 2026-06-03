//
//  CompositeKeyManager.swift
//  KeyMod
//
//  Created on 2025/6/21.
//

import Foundation

// Define shortcut key combinations
struct KeyCombo {
    let id: String
    let displayName: String
    let modifiers: [String]
    let key: String
    let category: ShortcutCategory
    let description: String
}

enum ShortcutCategory {
    case basic
    case system
    case file
    case navigation
    case tab
    case editing
}

class CompositeKeyManager: ObservableObject {
    private var keyboardManager: KeyboardManager?
    private let hapticManager = HapticFeedbackManager.shared
    
    // All available shortcuts organized by category
    let shortcuts: [KeyCombo] = [
        // Basic shortcuts
        KeyCombo(id: "copy", displayName: "Copy", modifiers: ["Cmd"], key: "C", category: .basic, description: "Copy selection"),
        KeyCombo(id: "paste", displayName: "Paste", modifiers: ["Cmd"], key: "V", category: .basic, description: "Paste from clipboard"),
        KeyCombo(id: "cut", displayName: "Cut", modifiers: ["Cmd"], key: "X", category: .basic, description: "Cut selection"),
        KeyCombo(id: "undo", displayName: "Undo", modifiers: ["Cmd"], key: "Z", category: .basic, description: "Undo last action"),
        KeyCombo(id: "selectAll", displayName: "All", modifiers: ["Cmd"], key: "A", category: .basic, description: "Select all"),
        
        // System shortcuts
        KeyCombo(id: "altF4", displayName: "Alt+F4", modifiers: ["Alt"], key: "F4", category: .system, description: "Close application"),
        KeyCombo(id: "ctrlAltDel", displayName: "Ctrl+Alt+Del", modifiers: ["Ctrl", "Alt"], key: "Delete", category: .system, description: "Security screen"),
        KeyCombo(id: "winL", displayName: "Win+L", modifiers: ["Cmd"], key: "L", category: .system, description: "Lock screen"),
        KeyCombo(id: "winD", displayName: "Win+D", modifiers: ["Cmd"], key: "D", category: .system, description: "Show desktop"),
        KeyCombo(id: "taskMgr", displayName: "Ctrl+Shift+Esc", modifiers: ["Ctrl", "Shift"], key: "Escape", category: .system, description: "Task Manager"),
        
        // File operations
        KeyCombo(id: "save", displayName: "Ctrl+S", modifiers: ["Ctrl"], key: "S", category: .file, description: "Save file"),
        KeyCombo(id: "new", displayName: "Ctrl+N", modifiers: ["Ctrl"], key: "N", category: .file, description: "New file"),
        KeyCombo(id: "open", displayName: "Ctrl+O", modifiers: ["Ctrl"], key: "O", category: .file, description: "Open file"),
        KeyCombo(id: "print", displayName: "Ctrl+P", modifiers: ["Ctrl"], key: "P", category: .file, description: "Print"),
        KeyCombo(id: "saveAs", displayName: "Ctrl+Shift+S", modifiers: ["Ctrl", "Shift"], key: "S", category: .file, description: "Save as"),
        
        // Navigation shortcuts
        KeyCombo(id: "find", displayName: "Ctrl+F", modifiers: ["Ctrl"], key: "F", category: .navigation, description: "Find"),
        KeyCombo(id: "replace", displayName: "Ctrl+H", modifiers: ["Ctrl"], key: "H", category: .navigation, description: "Find and replace"),
        KeyCombo(id: "goTo", displayName: "Ctrl+G", modifiers: ["Ctrl"], key: "G", category: .navigation, description: "Go to line"),
        KeyCombo(id: "home", displayName: "Home", modifiers: [], key: "Home", category: .navigation, description: "Go to beginning"),
        KeyCombo(id: "end", displayName: "End", modifiers: [], key: "End", category: .navigation, description: "Go to end"),
        
        // Tab management
        KeyCombo(id: "newTab", displayName: "Ctrl+T", modifiers: ["Ctrl"], key: "T", category: .tab, description: "New tab"),
        KeyCombo(id: "closeTab", displayName: "Ctrl+W", modifiers: ["Ctrl"], key: "W", category: .tab, description: "Close tab"),
        KeyCombo(id: "nextTab", displayName: "Ctrl+Tab", modifiers: ["Ctrl"], key: "Tab", category: .tab, description: "Next tab"),
        KeyCombo(id: "prevTab", displayName: "Ctrl+Shift+Tab", modifiers: ["Ctrl", "Shift"], key: "Tab", category: .tab, description: "Previous tab"),
        KeyCombo(id: "reopenTab", displayName: "Ctrl+Shift+T", modifiers: ["Ctrl", "Shift"], key: "T", category: .tab, description: "Reopen closed tab"),
        
        // Editing shortcuts
        KeyCombo(id: "redo", displayName: "Ctrl+Y", modifiers: ["Ctrl"], key: "Y", category: .editing, description: "Redo"),
        KeyCombo(id: "bold", displayName: "Ctrl+B", modifiers: ["Ctrl"], key: "B", category: .editing, description: "Bold text"),
        KeyCombo(id: "italic", displayName: "Ctrl+I", modifiers: ["Ctrl"], key: "I", category: .editing, description: "Italic text"),
        KeyCombo(id: "underline", displayName: "Ctrl+U", modifiers: ["Ctrl"], key: "U", category: .editing, description: "Underline text"),
        KeyCombo(id: "duplicate", displayName: "Ctrl+D", modifiers: ["Ctrl"], key: "D", category: .editing, description: "Duplicate line")
    ]
    
    init(keyboardManager: KeyboardManager? = nil) {
        self.keyboardManager = keyboardManager
    }
    
    func setKeyboardManager(_ manager: KeyboardManager) {
        self.keyboardManager = manager
    }
    
    // Execute a shortcut by ID
    func executeShortcut(_ shortcutId: String) {
        guard let shortcut = shortcuts.first(where: { $0.id == shortcutId }) else {
            print("Unknown shortcut: \(shortcutId)")
            return
        }
        
        executeKeyCombo(shortcut)
    }
    
    // Execute a key combination
    func executeKeyCombo(_ combo: KeyCombo) {
        guard let keyboardManager = keyboardManager else {
            print("KeyboardManager not set")
            return
        }
        
        // Trigger medium haptic feedback for key combinations
        hapticManager.triggerMediumFeedback()
        
        print("Executing: \(combo.displayName) - \(combo.description)")
        keyboardManager.handleKeyCombo(modifiers: combo.modifiers, key: combo.key)
    }
    
    // Get shortcuts by category
    func getShortcuts(for category: ShortcutCategory) -> [KeyCombo] {
        return shortcuts.filter { $0.category == category }
    }
    
    // Get all shortcuts organized by category
    func getShortcutsByCategory() -> [ShortcutCategory: [KeyCombo]] {
        return Dictionary(grouping: shortcuts, by: { $0.category })
    }
    
    // Search shortcuts by name or description
    func searchShortcuts(_ query: String) -> [KeyCombo] {
        let lowercaseQuery = query.lowercased()
        return shortcuts.filter { 
            $0.displayName.lowercased().contains(lowercaseQuery) ||
            $0.description.lowercased().contains(lowercaseQuery)
        }
    }
    
    // Get popular/frequently used shortcuts
    func getPopularShortcuts() -> [KeyCombo] {
        return shortcuts.filter { 
            ["copy", "paste", "cut", "undo", "selectAll", "save", "find", "newTab", "closeTab"].contains($0.id)
        }
    }
    
    // Convenience methods for common shortcuts
    func copy() { executeShortcut("copy") }
    func paste() { executeShortcut("paste") }
    func cut() { executeShortcut("cut") }
    func undo() { executeShortcut("undo") }
    func selectAll() { executeShortcut("selectAll") }
    func save() { executeShortcut("save") }
    func find() { executeShortcut("find") }
    func newTab() { executeShortcut("newTab") }
    func closeTab() { executeShortcut("closeTab") }
    func altF4() { executeShortcut("altF4") }
    func ctrlAltDel() { executeShortcut("ctrlAltDel") }
    func winL() { executeShortcut("winL") }
    func winD() { executeShortcut("winD") }
    func clearModifiers() {
        keyboardManager?.clearAllModifiers()
    }
}

/*
Example usage for future enhancements:

// Advanced shortcut panel view
struct ShortcutPanelView: View {
    @ObservedObject var compositeKeyManager: CompositeKeyManager
    @State private var selectedCategory: ShortcutCategory = .basic
    
    var body: some View {
        VStack {
            // Category selector
            Picker("Category", selection: $selectedCategory) {
                Text("Basic").tag(ShortcutCategory.basic)
                Text("System").tag(ShortcutCategory.system)
                Text("File").tag(ShortcutCategory.file)
                Text("Navigation").tag(ShortcutCategory.navigation)
                Text("Tab").tag(ShortcutCategory.tab)
                Text("Editing").tag(ShortcutCategory.editing)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            // Shortcuts grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                ForEach(compositeKeyManager.getShortcuts(for: selectedCategory), id: \.id) { shortcut in
                    VStack {
                        Button(shortcut.displayName) {
                            compositeKeyManager.executeShortcut(shortcut.id)
                        }
                        .buttonStyle(.bordered)
                        
                        Text(shortcut.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
*/
