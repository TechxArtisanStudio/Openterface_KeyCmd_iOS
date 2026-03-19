import SwiftUI
import UniformTypeIdentifiers

struct ShortcutHubView: View {
    @StateObject private var keyboardManager: KeyboardManager
    @StateObject private var profileManager = ShortcutProfileManager.shared

    @State private var selectedProfileID: String?
    @State private var selectedCategoryID: String = myCategoryID
    @State private var myShortcuts: [ShortcutItem] = []
    @State private var dragOver = false
    @State private var dragOverIndex: Int?
    @State private var isReorderingMode = false
    @State private var showingImporter = false
    @State private var numpadExpanded = false
    @State private var numpadHidden = false

    private static let myCategoryID = "my"
    private static let lastProfileKey = "ShortcutHub_LastProfileID"

    init(keyboardManager: KeyboardManager) {
        _keyboardManager = StateObject(wrappedValue: keyboardManager)
    }

    private var selectedProfile: ShortcutProfileData? {
        guard let selectedProfileID else { return nil }
        return profileManager.allProfiles.first { $0.id == selectedProfileID }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130), spacing: 12)]
    }

    var body: some View {
        Group {
            if let profile = selectedProfile {
                profileDetailView(profile)
            } else {
                profilePickerView
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .onChange(of: selectedProfileID) { _ in
            loadMyShortcuts()
            selectedCategoryID = Self.myCategoryID
            persistSelectedProfile()
        }
        .onChange(of: myShortcuts) { _ in
            saveMyShortcuts()
        }
        .onAppear {
            restoreLastProfile()
        }
        .onDisappear {
            dragOver = false
            dragOverIndex = nil
            isReorderingMode = false
        }
    }

    private var profilePickerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shortcut Hub")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Choose a profile to load shortcuts for Blender, KiCAD, Nomad, or your own imported setup.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }

                profileSection(
                    title: "Built-in Profiles",
                    subtitle: "Bundled app presets",
                    profiles: profileManager.builtInProfiles,
                    emptyMessage: nil
                )

                profileSection(
                    title: "Custom Profiles",
                    subtitle: "Imported JSON profiles",
                    profiles: profileManager.userProfiles,
                    emptyMessage: "No custom profiles yet. Use Import to add one."
                )
            }
            .padding()
        }
    }

    private func profileSection(title: String, subtitle: String, profiles: [ShortcutProfileData], emptyMessage: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if profiles.isEmpty, let emptyMessage {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(profiles) { profile in
                        ProfileCard(profile: profile) {
                            selectedProfileID = profile.id
                        }
                    }
                }
            }
        }
    }

    private func profileDetailView(_ profile: ShortcutProfileData) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if !numpadExpanded || !profile.hasNumpad || numpadHidden {
                    headerView(profile)
                    tabBarView(profile)

                    ScrollView {
                        VStack(spacing: 16) {
                            if selectedCategoryID == Self.myCategoryID {
                                myShortcutsSection
                            } else if let category = profile.categories.first(where: { $0.id == selectedCategoryID }) {
                                categorySection(category)
                            }
                        }
                        .padding()
                    }
                    .background(Color(UIColor.systemGroupedBackground))
                }

                if profile.hasNumpad, let numpad = profile.numpad {
                    numpadToggleBar(profile)

                    if !numpadHidden {
                        NumpadGridView(keys: numpad, keyboardManager: keyboardManager)
                            .frame(maxHeight: numpadExpanded ? .infinity : geometry.size.height * 0.3)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                            .background(Color(UIColor.systemBackground))
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }

    private func numpadToggleBar(_ profile: ShortcutProfileData) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Image(systemName: "grid.circle.fill")
                    .foregroundColor(colorFromHex(profile.themeColorHex))
                Text("Viewport Numpad")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()

                if !numpadHidden {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            numpadExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: numpadExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.semibold))
                            .foregroundColor(colorFromHex(profile.themeColorHex))
                            .padding(6)
                            .background(colorFromHex(profile.themeColorHex).opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        numpadHidden.toggle()
                        if numpadHidden { numpadExpanded = false }
                    }
                } label: {
                    Image(systemName: numpadHidden ? "eye.slash" : "eye")
                        .font(.body.weight(.semibold))
                        .foregroundColor(numpadHidden ? .secondary : colorFromHex(profile.themeColorHex))
                        .padding(6)
                        .background((numpadHidden ? Color.secondary : colorFromHex(profile.themeColorHex)).opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .background(Color(UIColor.systemBackground))
    }

    private func headerView(_ profile: ShortcutProfileData) -> some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(profileManager.allProfiles) { p in
                    Button {
                        selectedProfileID = p.id
                    } label: {
                        Label(p.name, systemImage: p.icon)
                    }
                }

                Divider()

                Button {
                    showingImporter = true
                } label: {
                    Label("Import Profile…", systemImage: "plus.circle")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: profile.icon)
                        .foregroundColor(colorFromHex(profile.themeColorHex))
                    Text(profile.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Tap to send shortcuts. Drag items into ⭐ My.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }

    private func tabBarView(_ profile: ShortcutProfileData) -> some View {
        HStack(spacing: 0) {
            // Fixed ⭐ My button
            Button {
                selectedCategoryID = Self.myCategoryID
            } label: {
                Text("⭐ My")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedCategoryID == Self.myCategoryID ? Color.blue : Color.gray.opacity(0.18))
                    .foregroundColor(selectedCategoryID == Self.myCategoryID ? .white : .primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading)
            .onDrop(of: [UTType.data.identifier], isTargeted: nil) { providers in
                handleDropOnMyTab(providers)
            }

            // Scrollable category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profile.categories) { category in
                    Button {
                        selectedCategoryID = category.id
                    } label: {
                        HStack(spacing: 6) {
                            if let icon = category.icon {
                                Image(systemName: icon)
                            }
                            Text(category.name)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedCategoryID == category.id ? colorFromHex(category.colorHex) : Color.gray.opacity(0.18))
                        .foregroundColor(selectedCategoryID == category.id ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    private func categorySection(_ category: ShortcutCategoryData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let icon = category.icon {
                    Image(systemName: icon)
                        .foregroundColor(colorFromHex(category.colorHex))
                }
                Text(category.name)
                    .font(.headline)
                Spacer()
                Text("\(category.shortcuts.count) shortcuts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(category.shortcuts) { shortcut in
                    ShortcutHubCard(
                        shortcut: shortcut,
                        accentColor: colorFromHex(category.colorHex),
                        backgroundColor: nil,
                        isCompact: false
                    ) {
                        executeShortcut(shortcut)
                    }
                    .onDrag {
                        makeItemProvider(for: shortcut)
                    }
                }
            }
        }
    }

    private var myShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Shortcuts")
                .font(.headline)

            Text("Drag shortcuts here from any category to build a quick-access profile-specific menu.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if myShortcuts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "star.square.on.square")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("No shortcuts saved yet")
                        .font(.headline)
                    Text("Switch to a category and drag a shortcut into My.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(dragOver ? Color.blue.opacity(0.12) : Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(myShortcuts.indices, id: \.self) { index in
                        let shortcut = myShortcuts[index]
                        let isBeingDraggedOver = dragOverIndex == index

                        ShortcutHubCard(
                            shortcut: shortcut,
                            accentColor: .blue,
                            backgroundColor: shortcut.colorHex.flatMap { colorFromHex($0) },
                            isCompact: false
                        ) {
                            executeShortcut(shortcut)
                        }
                        .opacity(isBeingDraggedOver ? 0.72 : 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isReorderingMode ? Color.blue : Color.green, lineWidth: isBeingDraggedOver ? 3 : 0)
                        )
                        .overlay(alignment: .topTrailing) {
                            if isBeingDraggedOver {
                                Image(systemName: isReorderingMode ? "arrow.left.arrow.right.circle.fill" : "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(isReorderingMode ? .blue : .green)
                                    .padding(8)
                            }
                        }
                        .onDrag {
                            makeItemProvider(for: shortcut)
                        }
                        .onDrop(of: [UTType.data.identifier], delegate: ShortcutItemDropDelegate(
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
                                ForEach(shortcutCardColorTemplates, id: \.hex) { color in
                                    Button(color.name) {
                                        setColorForShortcut(shortcut, color: color.hex)
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
        }
        .padding()
        .background(dragOver ? Color.blue.opacity(0.08) : Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onDrop(of: [UTType.data.identifier], isTargeted: $dragOver) { providers in
            handleDropIntoMyShortcuts(providers)
        }
    }

    private func makeItemProvider(for shortcut: ShortcutItem) -> NSItemProvider {
        if let data = try? JSONEncoder().encode(shortcut) {
            let provider = NSItemProvider(item: data as NSData, typeIdentifier: UTType.data.identifier)
            provider.suggestedName = shortcut.description
            return provider
        }
        return NSItemProvider(object: NSString(string: shortcut.description))
    }

    private func executeShortcut(_ shortcut: ShortcutItem) {
        if let modifier = shortcut.modifier, !modifier.isEmpty {
            let modifiers = modifier.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
            keyboardManager.handleKeyCombo(modifiers: modifiers, key: shortcut.keyCode)
            return
        }

        if shortcut.keyCode.contains("+") {
            let components = shortcut.keyCode.components(separatedBy: "+")
            if components.count >= 2 {
                let modifiers = Array(components.dropLast())
                if let key = components.last {
                    keyboardManager.handleKeyCombo(modifiers: modifiers, key: key)
                    return
                }
            }
        }

        keyboardManager.handleKeyPress(shortcut.keyCode)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                try profileManager.addCustomProfile(from: data)
            } catch {
                print("⚠️ ShortcutHubView: Failed to import profile – \(error)")
            }
        case .failure(let error):
            print("⚠️ ShortcutHubView: File import failed – \(error)")
        }
    }

    private func handleDropOnMyTab(_ providers: [NSItemProvider]) -> Bool {
        selectedCategoryID = Self.myCategoryID
        return handleDropIntoMyShortcuts(providers)
    }

    private func handleDropIntoMyShortcuts(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
            guard let data,
                  let shortcut = try? JSONDecoder().decode(ShortcutItem.self, from: data) else {
                return
            }

            DispatchQueue.main.async {
                addToMyShortcuts(shortcut)
                selectedCategoryID = Self.myCategoryID
            }
        }

        return true
    }

    private func addToMyShortcuts(_ shortcut: ShortcutItem) {
        if !myShortcuts.contains(shortcut) {
            myShortcuts.append(shortcut)
        }
    }

    private func removeFromMyShortcuts(_ shortcut: ShortcutItem) {
        myShortcuts.removeAll { $0.id == shortcut.id }
    }

    private func setColorForShortcut(_ shortcut: ShortcutItem, color: String?) {
        guard let index = myShortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        myShortcuts[index].colorHex = color
    }

    private func loadMyShortcuts() {
        guard let selectedProfileID else {
            myShortcuts = []
            return
        }

        myShortcuts = profileManager.myShortcuts(for: selectedProfileID)
    }

    private func saveMyShortcuts() {
        guard let selectedProfileID else { return }
        profileManager.updateMyShortcuts(for: selectedProfileID, items: myShortcuts)
    }

    private func restoreLastProfile() {
        guard selectedProfileID == nil else { return }
        if let savedID = UserDefaults.standard.string(forKey: Self.lastProfileKey),
           profileManager.allProfiles.contains(where: { $0.id == savedID }) {
            selectedProfileID = savedID
        } else if let first = profileManager.allProfiles.first {
            selectedProfileID = first.id
        }
    }

    private func persistSelectedProfile() {
        if let selectedProfileID {
            UserDefaults.standard.set(selectedProfileID, forKey: Self.lastProfileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.lastProfileKey)
        }
    }
}

private struct ProfileCard: View {
    let profile: ShortcutProfileData
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: profile.icon)
                        .font(.title2)
                        .foregroundColor(colorFromHex(profile.themeColorHex))

                    Spacer()

                    if profile.hasNumpad {
                        Image(systemName: "grid.circle")
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(profile.categories.count) categories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [colorFromHex(profile.themeColorHex).opacity(0.18), Color(UIColor.secondarySystemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutHubCard: View {
    let shortcut: ShortcutItem
    let accentColor: Color
    let backgroundColor: Color?
    let isCompact: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            isPressed = true
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isPressed = false
                action()
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    if let modifier = shortcut.modifier, !modifier.isEmpty {
                        ForEach(modifier.components(separatedBy: "+"), id: \.self) { mod in
                            MiniKeyCapsule(key: mod.trimmingCharacters(in: .whitespaces), isModifier: true, isPressed: isPressed)
                        }
                        Text("+")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    MiniKeyCapsule(key: shortcut.key, isModifier: false, isPressed: isPressed)
                    Spacer()
                }

                Text(shortcut.description)
                    .font(isCompact ? .caption : .subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Rectangle()
                    .fill(accentColor)
                    .frame(height: 3)
                    .clipShape(Capsule())
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: isCompact ? 84 : 102, alignment: .leading)
            .background(backgroundColor ?? Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .scaleEffect(isPressed ? 0.97 : 1)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct MiniKeyCapsule: View {
    let key: String
    let isModifier: Bool
    let isPressed: Bool

    var body: some View {
        Text(key)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isPressed
                    ? (isModifier ? Color.orange.opacity(0.6) : Color.blue.opacity(0.6))
                    : (isModifier ? Color.orange.opacity(0.82) : Color.blue.opacity(0.82))
            )
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ShortcutItemDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var shortcuts: [ShortcutItem]
    @Binding var dragOverIndex: Int?
    @Binding var isReorderingMode: Bool

    func performDrop(info: DropInfo) -> Bool {
        dragOverIndex = nil
        isReorderingMode = false

        guard let provider = info.itemProviders(for: [UTType.data.identifier]).first else {
            return false
        }

        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
            guard let data,
                  let draggedShortcut = try? JSONDecoder().decode(ShortcutItem.self, from: data) else {
                return
            }

            DispatchQueue.main.async {
                if let fromIndex = shortcuts.firstIndex(where: { $0 == draggedShortcut }) {
                    if fromIndex != targetIndex {
                        let movedShortcut = shortcuts.remove(at: fromIndex)
                        let insertIndex = max(0, min(targetIndex, shortcuts.count))
                        shortcuts.insert(movedShortcut, at: insertIndex)
                    }
                } else if !shortcuts.contains(draggedShortcut) {
                    shortcuts.insert(draggedShortcut, at: min(targetIndex, shortcuts.count))
                }
            }
        }

        return true
    }

    func dropEntered(info: DropInfo) {
        dragOverIndex = targetIndex

        guard let provider = info.itemProviders(for: [UTType.data.identifier]).first else { return }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
            guard let data,
                  let draggedShortcut = try? JSONDecoder().decode(ShortcutItem.self, from: data) else {
                return
            }

            DispatchQueue.main.async {
                isReorderingMode = shortcuts.contains { $0 == draggedShortcut }
            }
        }
    }

    func dropExited(info: DropInfo) {
        dragOverIndex = nil
        isReorderingMode = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.data.identifier])
    }
}

private let shortcutCardColorTemplates: [(name: String, hex: String)] = [
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

private func colorFromHex(_ hex: String) -> Color {
    var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    sanitized = sanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0
    Scanner(string: sanitized).scanHexInt64(&rgb)

    let r = Double((rgb & 0xFF0000) >> 16) / 255.0
    let g = Double((rgb & 0x00FF00) >> 8) / 255.0
    let b = Double(rgb & 0x0000FF) / 255.0
    return Color(red: r, green: g, blue: b)
}

#Preview {
    ShortcutHubView(keyboardManager: KeyboardManager(bleManager: BLEManager()))
}