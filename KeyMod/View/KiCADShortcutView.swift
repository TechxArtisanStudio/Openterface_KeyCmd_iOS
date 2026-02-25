import SwiftUI

struct Shortcut: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let key: String
    let keyCode: String
    var colorHex: String? // Optional color hex string
    
    init(id: UUID = UUID(), title: String, key: String, keyCode: String, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.key = key
        self.keyCode = keyCode
        self.colorHex = colorHex
    }
    
    // Custom Equatable implementation - compares based on content, not just ID
    static func == (lhs: Shortcut, rhs: Shortcut) -> Bool {
        return lhs.title == rhs.title && 
               lhs.key == rhs.key && 
               lhs.keyCode == rhs.keyCode &&
               lhs.colorHex == rhs.colorHex
    }
}

struct KiCADShortcutView: View {
    @ObservedObject var keyboardManager: KeyboardManager
    @State private var selectedTab = 0
    
    @AppStorage("myShortcuts") private var myShortcutsData: Data = Data()
    @State private var myShortcuts: [Shortcut] = []
    @State private var dragOver = false
    @State private var dragOverIndex: Int? = nil
    @State private var isReorderingMode = false
    
    private let tabTitles = [
        "⭐ My Shortcuts",
        "📏 View & Zoom",
        "🧲 Layers",
        "🧱 Drawing & Edit",
        "🔁 Components",
        "🧠 Properties",
        "🛠️ PCB Design",
        "📂 File & Misc"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            tabSelector
            
            // Content area
            ScrollView {
                VStack(spacing: 12) {
                    switch selectedTab {
                    case 0:
                        myShortcutsSection
                    case 1:
                        viewZoomSection
                    case 2:
                        layersDisplaySection
                    case 3:
                        drawingEditingSection
                    case 4:
                        componentHandlingSection
                    case 5:
                        editingPropertiesSection
                    case 6:
                        pcbDesignSection
                    case 7:
                        fileMiscSection
                    default:
                        myShortcutsSection
                    }
                }
                .padding()
            }
        }
        .background(Color(UIColor.systemBackground))
        .onAppear(perform: loadMyShortcuts)
        .onChange(of: myShortcuts) { _ in saveMyShortcuts() }
        .onDisappear {
            // Clear drag state when view disappears
            dragOverIndex = nil
            isReorderingMode = false
        }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 8) {
            // Fixed My Shortcuts tab
            Button(action: {
                selectedTab = 0
            }) {
                Text(tabTitles[0])
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedTab == 0 ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(selectedTab == 0 ? .white : .primary)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .onDrop(of: ["public.data"], isTargeted: nil) { providers in
                if let provider = providers.first {
                    _ = provider.loadDataRepresentation(forTypeIdentifier: "public.data") { data, _ in
                        if let data = data, let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) {
                            DispatchQueue.main.async {
                                if !myShortcuts.contains(shortcut) {
                                    myShortcuts.append(shortcut)
                            }
                            selectedTab = 0
                        }
                    }
                }
                return true
            }
            return false
        }
        
        // Scrollable other tabs
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(1..<tabTitles.count, id: \.self) { index in
                    Button(action: {
                        selectedTab = index
                    }) {
                        Text(tabTitles[index])
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedTab == index ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(selectedTab == index ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
        }
    }
    // End of HStack for tabSelector
    .padding(.vertical, 8)
    .background(Color(UIColor.secondarySystemBackground))
}
    
    // MARK: - Show All Shortcuts Section
    private var showAllShortcutsSection: some View {
        VStack(spacing: 16) {
            Text("📋 All KiCAD Shortcuts")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Use the individual tabs above to access specific shortcut categories.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            
            // Simple test buttons to verify basic functionality
            VStack(spacing: 12) {
                Button("Test: Zoom In (F1)") {
                    handleShortcutAction("F1")
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                
                Button("Test: Save (Ctrl+S)") {
                    handleShortcutAction("Ctrl+S")
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
    }

    // MARK: - View & Zoom Section
    private var viewZoomSection: some View {
        VStack(spacing: 8) {
            sectionHeader("📏 View & Zoom")
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                shortcutButton("Zoom In", key: "F1", keyCode: "F1")
                shortcutButton("Zoom Out", key: "F2", keyCode: "F2")
                shortcutButton("Redraw Zoom", key: "F3", keyCode: "F3")
                shortcutButton("Center Zoom", key: "F4", keyCode: "F4")
                shortcutButton("Fit on Screen", key: "Home", keyCode: "Home")
                shortcutButton("Switch Units", key: "Ctrl+U", keyCode: "Ctrl+U")
                shortcutButton("Reset Coordinates", key: "Space", keyCode: "Space")
            }
        }
    }
    
    // MARK: - Drawing & Editing Section
    private var drawingEditingSection: some View {
        VStack(spacing: 8) {
            sectionHeader("🧱 Drawing & Editing")
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                shortcutButton("Begin Wire", key: "W", keyCode: "W")
                shortcutButton("Begin Bus", key: "B", keyCode: "B")
                shortcutButton("Add Label", key: "L", keyCode: "L")
                shortcutButton("Add Power", key: "P", keyCode: "P")
                shortcutButton("Add Junction", key: "J", keyCode: "J")
                shortcutButton("Add Sheet", key: "S", keyCode: "S")
                shortcutButton("No Connect Flag", key: "Q", keyCode: "Q")
                shortcutButton("Hierarchical Label", key: "H", keyCode: "H")
                shortcutButton("Add Wire Entry", key: "Z", keyCode: "Z")
                shortcutButton("Add Bus Entry", key: "/", keyCode: "/")
                shortcutButton("End Line/Wire/Bus", key: "K", keyCode: "K")
            }
        }
    }
    
    // MARK: - Component Handling Section
    private var componentHandlingSection: some View {
        VStack(spacing: 8) {
            sectionHeader("🔁 Component Handling")
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                shortcutButton("Add Component", key: "A", keyCode: "A")
                shortcutButton("Move Item", key: "M", keyCode: "M")
                shortcutButton("Copy Item", key: "C", keyCode: "C")
                shortcutButton("Drag Item", key: "G", keyCode: "G")
                shortcutButton("Rotate Item", key: "R", keyCode: "R")
                shortcutButton("Mirror X Component", key: "X", keyCode: "X")
                shortcutButton("Mirror Y Component", key: "Y", keyCode: "Y")
                shortcutButton("Flip Item", key: "F", keyCode: "F")
                shortcutButton("Orient Normal", key: "N", keyCode: "N")
            }
        }
    }
    
    // MARK: - Editing Properties Section
    private var editingPropertiesSection: some View {
        VStack(spacing: 8) {
            sectionHeader("🧠 Editing Properties")
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                shortcutButton("Edit Item", key: "E", keyCode: "E")
                shortcutButton("Edit Value", key: "V", keyCode: "V")
                shortcutButton("Edit Reference", key: "U", keyCode: "U")
                shortcutButton("Edit Footprint", key: "F", keyCode: "F")
                shortcutButton("Get/Move Footprint", key: "T", keyCode: "T")
            }
        }
    }
    
    // MARK: - PCB Design Section
    private var pcbDesignSection: some View {
        VStack(spacing: 8) {
            sectionHeader("🛠️ Board Design (PCBNew)")
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                shortcutButton("Add Track", key: "X", keyCode: "X")
                shortcutButton("Add Via", key: "V", keyCode: "V")
                shortcutButton("Add Microvia", key: "Ctrl+V", keyCode: "Ctrl+V")
                shortcutButton("Switch Track Posture", key: "/", keyCode: "F4")
                shortcutButton("Drag Track w/ Slope", key: "D", keyCode: "D")
                shortcutButton("End Track", key: "End", keyCode: "End")
                shortcutButton("Add Module", key: "O", keyCode: "O")
                shortcutButton("Track Width ↑", key: "W", keyCode: "W")
                shortcutButton("Track Width ↓", key: "Ctrl+W", keyCode: "Ctrl+W")
            }
        }
    }
    
    // MARK: - File & Misc Section
    private var fileMiscSection: some View {
        VStack(spacing: 8) {
            sectionHeader("📂 File and Misc")
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                shortcutButton("Save Board", key: "Ctrl+S", keyCode: "Ctrl+S")
                shortcutButton("Load Board", key: "Ctrl+L", keyCode: "Ctrl+L")
                shortcutButton("Find Item", key: "Ctrl+F", keyCode: "Ctrl+F")
                shortcutButton("Undo", key: "Ctrl+Z", keyCode: "Ctrl+Z")
                shortcutButton("Redo", key: "Ctrl+Y", keyCode: "Ctrl+Y")
                shortcutButton("Delete Item", key: "Del", keyCode: "Delete")
                shortcutButton("Delete Track Segment", key: "BkSp", keyCode: "Backspace")
            }
        }
    }
    
    // MARK: - Layers & Display Section
    private var layersDisplaySection: some View {
        VStack(spacing: 8) {
            sectionHeader("🧲 Layers & Display")
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                shortcutButton("Copper Layer", key: "PgDn", keyCode: "PageDown")
                shortcutButton("Component Layer", key: "PgUp", keyCode: "PageUp")
                shortcutButton("Inner Layer 1", key: "F5", keyCode: "F5")
                shortcutButton("Inner Layer 2", key: "F6", keyCode: "F6")
                shortcutButton("Next Layer", key: "+", keyCode: "+")
                shortcutButton("Previous Layer", key: "-", keyCode: "-")
                shortcutButton("High Contrast Mode", key: "H", keyCode: "H")
                shortcutButton("Mirror Block Selection", key: "Shift+LMB", keyCode: "Shift")
            }
        }
    }
    
    // MARK: - Helper Views
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }
    
    private func shortcutButton(_ title: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(key)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func compactShortcutButton(_ title: String, key: String, keyCode: String) -> some View {
        Button {
            handleShortcutAction(keyCode)
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                Text(key)
                    .font(.system(size: 9))
                    .fontWeight(.bold)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - My Shortcuts Section (Drag-and-Drop)
    private var myShortcutsSection: some View {
        VStack(spacing: 16) {
            Text("Drag shortcuts to me from other tabs for quick access.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            
            if myShortcuts.isEmpty {
                Text("No shortcuts yet. Drag your favorites here!")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 16) {
                    ForEach(myShortcuts.indices, id: \.self) { index in
                        let shortcut = myShortcuts[index]
                        let shortcutButtonView = shortcutButton(shortcut.title, key: shortcut.key, keyCode: shortcut.keyCode, colorHex: shortcut.colorHex)
                        let isBeingDraggedOver = dragOverIndex == index
                        
                        VStack {
                            ZStack {
                                shortcutButtonView
                                    .opacity(isBeingDraggedOver ? 0.7 : 1.0)
                                    .overlay(
                                        // Add a colored border based on operation type
                                        RoundedRectangle(cornerRadius: 24)
                                            .stroke(isReorderingMode ? Color.blue : Color.green, lineWidth: isBeingDraggedOver ? 3 : 0)
                                            .animation(.easeInOut(duration: 0.2), value: isBeingDraggedOver)
                                    )
                                
                                // Show different icons based on operation mode
                                if isBeingDraggedOver {
                                    VStack(spacing: 4) {
                                        if isReorderingMode {
                                            // Show swap icon for reordering
                                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                                                .font(.system(size: 32))
                                                .foregroundColor(.blue)
                                        } else {
                                            // Show add icon for new shortcuts
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 32))
                                                .foregroundColor(.green)
                                        }
                                        
                                        Text(isReorderingMode ? "SWAP" : "ADD")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule()
                                                    .fill(isReorderingMode ? Color.blue : Color.green)
                                                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                            )
                                    }
                                    .background(
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 44, height: 44)
                                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                    )
                                    .transition(.scale.combined(with: .opacity))
                                    .animation(.easeInOut(duration: 0.2), value: isBeingDraggedOver)
                                }
                            }
                            .onDrop(of: ["public.data"], delegate: ShortcutDropDelegate(
                                targetIndex: index,
                                shortcuts: $myShortcuts,
                                dragOverIndex: $dragOverIndex,
                                isReorderingMode: $isReorderingMode
                            ))
                            .contextMenu {
                                Button("Remove") {
                                    removeFromMyShortcuts(shortcut)
                                }
                                Menu("Set Color") {
                                    ForEach(colorTemplates, id: \.hex) { color in
                                        Button(action: {
                                            setColorForShortcut(shortcut, color: color.hex)
                                        }) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(colorFromHex(color.hex))
                                                    .frame(height: 32)
                                                Text(color.name)
                                                    .foregroundColor(.primary)
                                                    .bold()
                                            }
                                        }
                                    }
                                    Button("Default") {
                                        setColorForShortcut(shortcut, color: nil)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .onDrop(of: ["public.data"], isTargeted: $dragOver) { providers in
            if let provider = providers.first {
                _ = provider.loadDataRepresentation(forTypeIdentifier: "public.data") { data, _ in
                    if let data = data, let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) {
                        DispatchQueue.main.async {
                            addToMyShortcuts(shortcut)
                        }
                    }
                }
                return true
            }
            return false
        }
        .background(dragOver ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(12)
    }
    
    // MARK: - Helper for Drag-and-Drop
    private func addToMyShortcuts(_ shortcut: Shortcut) {
        if !myShortcuts.contains(shortcut) {
            myShortcuts.append(shortcut)
        }
    }
    private func removeFromMyShortcuts(_ shortcut: Shortcut) {
        myShortcuts.removeAll { $0.id == shortcut.id }
    }
    private func loadMyShortcuts() {
        if let loaded = try? JSONDecoder().decode([Shortcut].self, from: myShortcutsData) {
            // Sanitize legacy hardcoded dark color (#23272F) saved previously
            myShortcuts = loaded.map { shortcut in
                var s = shortcut
                if let hex = s.colorHex, hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "#23272f" {
                    s.colorHex = nil
                }
                return s
            }
        }
    }
    private func saveMyShortcuts() {
        // Ensure we don't persist the legacy hardcoded color; convert it to nil before saving
        let sanitized = myShortcuts.map { shortcut -> Shortcut in
            var s = shortcut
            if let hex = s.colorHex, hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "#23272f" {
                s.colorHex = nil
            }
            return s
        }

        if let data = try? JSONEncoder().encode(sanitized) {
            myShortcutsData = data
        }
    }
    
    // MARK: - Drag-enabled Shortcut Button
    private func shortcutButton(_ title: String, key: String, keyCode: String, colorHex: String? = nil) -> some View {
        let shortcut = Shortcut(title: title, key: key, keyCode: keyCode, colorHex: colorHex)
        return Button {
            handleShortcutAction(keyCode)
        } label: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(key)
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.18))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
            .frame(width: 120, height: 120)
            .background(colorHex != nil ? colorFromHex(colorHex) : Color(UIColor.secondarySystemBackground))
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onDrag {
            let provider: NSItemProvider
            if let data = try? JSONEncoder().encode(shortcut) {
                provider = NSItemProvider(item: data as NSData, typeIdentifier: "public.data")
                
                // Set a custom drag preview description
                provider.suggestedName = "Reorder Shortcut"
            } else {
                provider = NSItemProvider(object: NSString(string: ""))
            }
            return provider
        }
    }
    
    private func handleShortcutAction(_ keyCode: String) {
        guard !keyCode.isEmpty else { return }
        
        if keyCode.contains("+") {
            let components = keyCode.components(separatedBy: "+")
            if components.count >= 2 {
                let modifiers = Array(components.dropLast())
                let key = components.last!
                keyboardManager.handleKeyCombo(modifiers: modifiers, key: key)
            }
        } else {
            keyboardManager.handleKeyPress(keyCode)
        }
    }
    
    private func setColorForShortcut(_ shortcut: Shortcut, color: String?) {
        if let idx = myShortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            var updated = myShortcuts[idx]
            updated.colorHex = color
            myShortcuts[idx] = updated
        }
    }
}

// MARK: - Drop Delegate for Reordering
struct ShortcutDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var shortcuts: [Shortcut]
    @Binding var dragOverIndex: Int?
    @Binding var isReorderingMode: Bool
    
    func performDrop(info: DropInfo) -> Bool {
        // Clear the drag over state
        dragOverIndex = nil
        isReorderingMode = false
        
        guard let provider = info.itemProviders(for: ["public.data"]).first else {
            return false
        }
        
        _ = provider.loadDataRepresentation(forTypeIdentifier: "public.data") { data, _ in
            guard let data = data,
                  let draggedShortcut = try? JSONDecoder().decode(Shortcut.self, from: data) else {
                return
            }
            
            DispatchQueue.main.async {
                // Debug: Print drag and drop information
                print("🔄 Drop operation - Target index: \(targetIndex)")
                print("🔄 Shortcuts count: \(shortcuts.count)")
                print("🔄 Dragged shortcut: \(draggedShortcut.title)")
                print("🔄 Dragged shortcut ID: \(draggedShortcut.id)")
                
                // Debug: Print all shortcut IDs in the list
                print("🔄 Current shortcut IDs in list:")
                for (index, shortcut) in shortcuts.enumerated() {
                    print("  Index \(index): \(shortcut.title) - ID: \(shortcut.id)")
                }
                
                // Check if this is a reordering operation (shortcut already exists in myShortcuts)
                // Use content-based comparison instead of ID-based since IDs might change during encoding/decoding
                if let fromIndex = shortcuts.firstIndex(where: { $0 == draggedShortcut }) {
                    print("🔄 Reordering detected - From index: \(fromIndex), Target index: \(targetIndex)")
                    // This is reordering within the same list
                    if fromIndex != targetIndex {
                        print("🔄 Executing reorder operation")
                        print("🔄 Moving from \(fromIndex) to \(targetIndex)")
                        
                        if abs(fromIndex - targetIndex) == 1 {
                            // Adjacent positions - just swap them
                            shortcuts.swapAt(fromIndex, targetIndex)
                            print("🔄 Adjacent swap: \(fromIndex) ↔ \(targetIndex)")
                        } else {
                            // Non-adjacent move - use remove/insert
                            let movedShortcut = shortcuts.remove(at: fromIndex)
                            
                            var insertIndex = targetIndex
                            // if fromIndex < targetIndex {
                            //     insertIndex = targetIndex - 1
                            // }
                            
                            insertIndex = max(0, min(insertIndex, shortcuts.count))
                            shortcuts.insert(movedShortcut, at: insertIndex)
                            print("🔄 Non-adjacent move: removed from \(fromIndex), inserted at \(insertIndex)")
                        }
                        
                        print("🔄 Final array: \(shortcuts.enumerated().map { "\($0.offset): \($0.element.title)" })")
                        print("🔄 Reorder completed")
                    } else {
                        print("🔄 Same position drop - No reordering needed")
                    }
                } else {
                    print("🔄 Adding new shortcut from another tab")
                    // This is adding a new shortcut from another tab
                    // Insert at the target position
                    if !shortcuts.contains(draggedShortcut) {
                        shortcuts.insert(draggedShortcut, at: min(targetIndex, shortcuts.count))
                        print("🔄 New shortcut added at index: \(min(targetIndex, shortcuts.count))")
                    } else {
                        print("🔄 Shortcut already exists in list")
                    }
                }
            }
        }
        
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Show visual feedback when drag enters this shortcut
        dragOverIndex = targetIndex
        
        // Check if we're in reordering mode by trying to decode the dragged item
        if let provider = info.itemProviders(for: ["public.data"]).first {
            _ = provider.loadDataRepresentation(forTypeIdentifier: "public.data") { data, _ in
                if let data = data,
                   let draggedShortcut = try? JSONDecoder().decode(Shortcut.self, from: data) {
                    DispatchQueue.main.async {
                        // If the dragged shortcut exists in our shortcuts, we're reordering
                        // Use content-based comparison instead of ID-based
                        isReorderingMode = shortcuts.contains { $0 == draggedShortcut }
                    }
                }
            }
        }
    }
    
    func dropExited(info: DropInfo) {
        // Remove visual feedback when drag exits this shortcut
        dragOverIndex = nil
        isReorderingMode = false
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Check if this is a reordering operation
        guard info.itemProviders(for: ["public.data"]).first != nil else {
            return DropProposal(operation: .cancel)
        }
        
        // For reordering operations, suggest move operation
        // This changes the cursor from + to a move cursor
        return DropProposal(operation: .move)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: ["public.data"])
    }
}

// MARK: - Color Templates
private let colorTemplates: [(name: String, hex: String)] = [
    ("Orange", "#FFB300"),
    ("Blue", "#29B6F6"),
    ("Green", "#66BB6A"),
    ("Purple", "#AB47BC"),
    ("Pink", "#EC407A"),
    ("Red-Orange", "#FF7043"),
    ("Olive", "#789262"),
    ("Brown", "#8D6E63"),
    ("Gray", "#BDBDBD")
]

private func colorFromHex(_ hex: String?) -> Color {
    guard let hex = hex else { return Color(UIColor.secondarySystemBackground) }
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
    var rgb: UInt64 = 0
    Scanner(string: hexSanitized).scanHexInt64(&rgb)
    let r = Double((rgb & 0xFF0000) >> 16) / 255.0
    let g = Double((rgb & 0x00FF00) >> 8) / 255.0
    let b = Double(rgb & 0x0000FF) / 255.0
    return Color(red: r, green: g, blue: b)
}

#Preview {
    KiCADShortcutView(keyboardManager: KeyboardManager(bleManager: BLEManager()))
}
