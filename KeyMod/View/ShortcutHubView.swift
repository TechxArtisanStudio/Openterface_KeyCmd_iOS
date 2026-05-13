import SwiftUI
import UniformTypeIdentifiers

struct ShortcutHubView: View {

    @StateObject private var keyboardManager: KeyboardManager
    @ObservedObject private var profileManager = ShortcutProfileManager.shared
    @ObservedObject private var stripManager   = Rows23StripProfileManager.shared

    // Hub navigation
    @State private var mainTab: Int = 0

    // App-profiles state
    @State private var selectedProfileID: String?
    @State private var selectedCategoryID: String = Self.myCategoryID
    @State private var myShortcuts: [ShortcutItem] = []
    @State private var showingProfileImporter = false
    @State private var showingCreateProfile   = false
    @State private var newProfileName         = ""

    // Strip state
    @State private var selectedStripProfileID: String?
    @State private var showingStripImporter      = false
    @State private var showingCreateStripProfile = false
    @State private var newStripProfileName       = ""
    @State private var showingResetStripConfirm  = false

    // Numpad (profile detail)
    @State private var numpadExpanded = false
    @State private var numpadHidden   = false

    // Shortcut editor
    @State private var editorContext: ShortcutEditorContext? = nil

    // Delete confirmation for profile category shortcuts
    @State private var deletingShortcut: ShortcutItem? = nil

    // Shortcut display style toggle
    @State private var displayStyle: ShortcutDisplayStyle = .list
    @State private var draggingItem: ShortcutItem? = nil

    private static let myCategoryID  = "my"

    init(keyboardManager: KeyboardManager) {
        _keyboardManager = StateObject(wrappedValue: keyboardManager)
    }

    // MARK: Computed

    private var selectedProfile: ShortcutProfileData? {
        guard let id = selectedProfileID else { return nil }
        return profileManager.allProfiles.first { $0.id == id }
    }

    private var selectedStripProfile: Rows23StripProfile? {
        guard let id = selectedStripProfileID else { return nil }
        return stripManager.profiles.first { $0.id == id }
    }

    // MARK: Body

    var body: some View {
        Group {
            if let profile = selectedProfile {
                profileDetailView(profile)
            } else if let strip = selectedStripProfile {
                stripDetailView(strip)
            } else {
                hubShell
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .fileImporter(
            isPresented: $showingProfileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { handleProfileImport($0) }
        .fileImporter(
            isPresented: $showingStripImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { handleStripImport($0) }
        .sheet(item: $editorContext) { ctx in
            ShortcutEditorSheet(context: ctx) { savedItem in
                handleEditorSave(savedItem, context: ctx)
                editorContext = nil
            }
        }
        .confirmationDialog(
            "Delete \"\(deletingShortcut?.description ?? "")\"?",
            isPresented: Binding(
                get: { deletingShortcut != nil },
                set: { if !$0 { deletingShortcut = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let shortcut = deletingShortcut, let profileId = selectedProfileID {
                    profileManager.deleteShortcutFromProfile(shortcutId: shortcut.id, inProfileId: profileId)
                    myShortcuts = profileManager.myShortcuts(for: profileId)
                }
                deletingShortcut = nil
            }
            Button("Cancel", role: .cancel) { deletingShortcut = nil }
        }
        .onChange(of: selectedProfileID) { _ in
            loadMyShortcuts()
            selectedCategoryID = Self.myCategoryID
            numpadExpanded = false
            numpadHidden   = false
        }
        .onChange(of: myShortcuts) { _ in
            saveMyShortcuts()
        }
    }

    // MARK: - Hub Shell

    private var hubShell: some View {
        VStack(spacing: 0) {
            hubHeader
            hubTabBar
            Divider()
            switch mainTab {
            case 1:  stripProfilesTabContent
            case 2:  page3TabContent
            default: appProfilesTabContent
            }
        }
    }

    private var hubHeader: some View {
        HStack(spacing: 8) {
            Text("Shortcut Hub")
                .font(.system(size: 22, weight: .bold))
            if let active = profileManager.activeProfile {
                Text(active.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var hubTabBar: some View {
        let tabs = ["App Profiles", "Fixed Strip", "Info"]
        return HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { idx in
                Button { mainTab = idx } label: {
                    Text(tabs[idx])
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(mainTab == idx ? Color.accentColor : Color.clear)
                        .foregroundColor(mainTab == idx ? .white : .secondary)
                        .animation(.easeInOut(duration: 0.15), value: mainTab)
                }
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Tab 0: App Profiles

    private var appProfilesTabContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    newProfileName = ""
                    showingCreateProfile = true
                } label: {
                    Label("Create Profile", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button { showingProfileImporter = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))

            Divider()

            if profileManager.allProfiles.isEmpty {
                Spacer()
                Text("No profiles yet.\nUse Create or Import to add one.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
                Spacer()
            } else {
                List {
                    ForEach(profileManager.allProfiles) { profile in
                        ProfileListRow(
                            profile: profile,
                            isActive: profile.id == profileManager.activeProfileId
                        ) {
                            selectedProfileID = profile.id
                        } onShare: {
                            shareProfile(profile)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color(UIColor.systemBackground))
                    }
                }
                .listStyle(.plain)
            }
        }
        .alert("New Profile", isPresented: $showingCreateProfile) {
            TextField("Profile name", text: $newProfileName)
            Button("Create") {
                let name = newProfileName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { profileManager.createUserProfile(name: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Profile Detail

    @ViewBuilder
    private func profileDetailView(_ profile: ShortcutProfileData) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {

                detailHeaderBar(profile: profile)

                if !numpadExpanded || !profile.hasNumpad || numpadHidden {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        let catCount = profile.categories.count
                        let scCount  = profile.categories.reduce(0) { $0 + $1.shortcuts.count }
                        Text("\(catCount) \(catCount == 1 ? "category" : "categories") · \(scCount) shortcuts")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemBackground))

                    Divider()

                    categoryTabBar(profile: profile)

                    Divider()

                    if selectedCategoryID == Self.myCategoryID {
                        myShortcutsListView
                    } else if let cat = profile.categories.first(where: { $0.id == selectedCategoryID }) {
                        browseShortcutsListView(category: cat, profile: profile)
                    }
                }

                if profile.hasNumpad, let numpad = profile.numpad {
                    numpadToggleBar(profile: profile)
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

    private func detailHeaderBar(profile: ShortcutProfileData) -> some View {
        HStack {
            Button("← Back") { selectedProfileID = nil }
                .buttonStyle(.borderless)
                .padding(.leading, 16)

            Spacer()

            // Toggle list / card view
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    displayStyle = displayStyle == .list ? .card : .list
                }
            } label: {
                Image(systemName: displayStyle == .list ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 8)

            Button {
                showAddShortcutEditor(profile: profile)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add Shortcut")
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private func categoryTabBar(profile: ShortcutProfileData) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryTabPill(id: Self.myCategoryID, label: "⭐ My")
                ForEach(profile.categories) { cat in
                    categoryTabPill(id: cat.id, label: cat.name,
                                    color: hubColorFromHex(cat.colorHex))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    @ViewBuilder
    private func categoryTabPill(id: String, label: String, color: Color = .accentColor) -> some View {
        Button { selectedCategoryID = id } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedCategoryID == id ? color : Color.gray.opacity(0.18))
                .foregroundColor(selectedCategoryID == id ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: My Shortcuts list

    private var myShortcutsListView: some View {
        Group {
            if myShortcuts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.square.on.square")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No favorites yet")
                        .font(.headline)
                    Text("Tap the bookmark icon in a category tab to add shortcuts here, or use + Add Shortcut.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayStyle == .card {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(myShortcuts) { shortcut in
                            ShortcutCardView(
                                shortcut: shortcut,
                                isDragging: draggingItem?.id == shortcut.id,
                                trailingIcon: "trash",
                                trailingColor: .red,
                                trailingAction: { removeFromMyShortcuts(shortcut) },
                                onTap: { executeShortcut(shortcut) },
                                onEdit: {
                                    openMyEditor(shortcut: shortcut)
                                }
                            )
                            .onDrag {
                                draggingItem = shortcut
                                return NSItemProvider(object: shortcut.id as NSString)
                            }
                            .onDrop(
                                of: [.plainText],
                                delegate: ShortcutCardDropDelegate(
                                    item: shortcut,
                                    items: $myShortcuts,
                                    draggingItem: $draggingItem
                                )
                            )
                        }
                    }
                    .padding(12)
                }
            } else {
                List {
                    ForEach(myShortcuts) { shortcut in
                        ShortcutListRow(
                            shortcut: shortcut,
                            trailingIcon: "trash",
                            trailingColor: .red,
                            trailingAction: { removeFromMyShortcuts(shortcut) },
                            onTap: { executeShortcut(shortcut) }
                        )
                        .listRowBackground(Color(UIColor.systemBackground))
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0))
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button { openMyEditor(shortcut: shortcut) } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onMove { from, to in myShortcuts.move(fromOffsets: from, toOffset: to) }
                    .onDelete { myShortcuts.remove(atOffsets: $0) }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    // MARK: Browse list

    private func browseShortcutsListView(category: ShortcutCategoryData,
                                         profile: ShortcutProfileData) -> some View {
        let isUser = profileManager.isUserProfile(id: profile.id)
        if displayStyle == .card {
            return AnyView(
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(category.shortcuts) { shortcut in
                            let bookmarked = myShortcuts.contains(shortcut)
                            ShortcutCardView(
                                shortcut: shortcut,
                                isDragging: false,
                                trailingIcon: bookmarked ? "bookmark.fill" : "bookmark",
                                trailingColor: bookmarked ? .accentColor : .secondary,
                                trailingAction: {
                                    if bookmarked { removeFromMyShortcuts(shortcut) }
                                    else          { addToMyShortcuts(shortcut) }
                                },
                                onTap: { executeShortcut(shortcut) },
                                onEdit: isUser ? { openBrowseEditor(profile: profile, category: category, shortcut: shortcut) } : nil
                            )
                            .contextMenu {
                                browseContextMenu(shortcut: shortcut, bookmarked: bookmarked,
                                                  isUser: isUser, profile: profile, category: category)
                            }
                        }
                    }
                    .padding(12)
                }
            )
        } else {
            return AnyView(
                List {
                    ForEach(category.shortcuts) { shortcut in
                        let bookmarked = myShortcuts.contains(shortcut)
                        ShortcutListRow(
                            shortcut: shortcut,
                            trailingIcon: bookmarked ? "bookmark.fill" : "bookmark",
                            trailingColor: bookmarked ? .accentColor : .secondary,
                            trailingAction: {
                                if bookmarked { removeFromMyShortcuts(shortcut) }
                                else          { addToMyShortcuts(shortcut) }
                            },
                            onTap: { executeShortcut(shortcut) }
                        )
                        .listRowBackground(Color(UIColor.systemBackground))
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0))
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if isUser {
                                Button { openBrowseEditor(profile: profile, category: category, shortcut: shortcut) } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isUser {
                                Button(role: .destructive) { deletingShortcut = shortcut } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .contextMenu {
                            browseContextMenu(shortcut: shortcut, bookmarked: bookmarked,
                                             isUser: isUser, profile: profile, category: category)
                        }
                    }
                }
                .listStyle(.plain)
            )
        }
    }

    // MARK: Numpad toggle bar

    private func numpadToggleBar(profile: ShortcutProfileData) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Image(systemName: "grid.circle.fill")
                    .foregroundColor(hubColorFromHex(profile.themeColorHex))
                Text("Viewport Numpad")
                    .font(.headline)
                Spacer()

                if !numpadHidden {
                    numpadIconButton(
                        icon: numpadExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        color: hubColorFromHex(profile.themeColorHex)
                    ) { withAnimation(.easeInOut(duration: 0.25)) { numpadExpanded.toggle() } }
                }

                numpadIconButton(
                    icon: numpadHidden ? "eye.slash" : "eye",
                    color: numpadHidden ? .secondary : hubColorFromHex(profile.themeColorHex)
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        numpadHidden.toggle()
                        if numpadHidden { numpadExpanded = false }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
        }
    }

    private func numpadIconButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundColor(color)
                .padding(6)
                .background(color.opacity(0.15))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 1: Fixed Strip Profiles

    private var stripProfilesTabContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    newStripProfileName = ""
                    showingCreateStripProfile = true
                } label: {
                    Label("Create", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button { showingStripImporter = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))

            Divider()

            List {
                ForEach(stripManager.profiles) { strip in
                    StripProfileListRow(
                        strip: strip,
                        isActive: strip.id == stripManager.activeProfileId,
                        onTap: { selectedStripProfileID = strip.id },
                        onSetActive: { stripManager.activeProfileId = strip.id }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color(UIColor.systemBackground))
                }
                .onDelete { indices in
                    indices.forEach { stripManager.deleteProfile(id: stripManager.profiles[$0].id) }
                }
            }
            .listStyle(.plain)
        }
        .alert("New Strip Profile", isPresented: $showingCreateStripProfile) {
            TextField("Profile name", text: $newStripProfileName)
            Button("Create") {
                let name = newStripProfileName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { stripManager.createProfile(name: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Strip Detail

    private func stripDetailView(_ strip: Rows23StripProfile) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("← Back") { selectedStripProfileID = nil }
                    .buttonStyle(.borderless)
                    .padding(.leading, 16)

                Spacer()

                Button("Reset") { showingResetStripConfirm = true }
                    .buttonStyle(.borderless)
                    .foregroundColor(.orange)
                    .padding(.trailing, 16)
            }
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemBackground))
            .confirmationDialog(
                "Reset \"\(strip.name)\" to factory layout?",
                isPresented: $showingResetStripConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    stripManager.resetProfileToFactory(id: strip.id)
                    selectedStripProfileID = nil
                }
                Button("Cancel", role: .cancel) {}
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(strip.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                let n = strip.slotMap.count
                Text(n == 0
                     ? "Factory layout — no slot overrides"
                     : "\(n) slot override\(n == 1 ? "" : "s")")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemBackground))

            Divider()

            StripSlotCatalogView(strip: strip)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Tab 2: Page 3 Info

    private var page3TabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Fixed Strip Layout")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)

                Text("""
The keyboard strip above the main keyboard has 4 swipeable pages (rows 2–3), each showing two rows of 7 keys.

Page 0 — Function keys F1–F12 and the = key
Page 1 — Modifier keys and navigation arrows (default page)
Page 2 — Punctuation symbols; local Fn toggles between two symbol layers
Page 3 — Row 2: quick-toggle slots for App Profile shortcuts. Row 3: quick-toggle slots for Rows 2–3 strip profiles.

Use the Fixed Strip tab to create, import, and customize strip profiles. Each profile stores a set of slot overrides that replace the factory key assignments shown in the catalog.
""")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
            .padding(16)
        }
    }

    // MARK: - Shortcut editor helpers

    private func showAddShortcutEditor(profile: ShortcutProfileData) {
        let useCategory = selectedCategoryID != Self.myCategoryID
                          && profileManager.isUserProfile(id: profile.id)
        editorContext = ShortcutEditorContext(
            profileId: profile.id,
            categoryId: useCategory ? selectedCategoryID : nil,
            existing: nil,
            source: useCategory ? .category : .myShortcuts
        )
    }

    private func handleEditorSave(_ item: ShortcutItem, context: ShortcutEditorContext) {
        let isEdit = context.existing != nil
        switch context.source {
        case .myShortcuts:
            if isEdit {
                myShortcuts = myShortcuts.map { $0.id == item.id ? item : $0 }
            } else {
                if !myShortcuts.contains(item) {
                    myShortcuts.append(item)
                }
            }
        case .category:
            if isEdit {
                profileManager.updateShortcutInProfile(item, inProfileId: context.profileId)
                myShortcuts = profileManager.myShortcuts(for: context.profileId)
            } else {
                profileManager.addShortcut(item, toCategoryId: context.categoryId, inProfileId: context.profileId)
            }
        }
    }

    private func openMyEditor(shortcut: ShortcutItem) {
        editorContext = ShortcutEditorContext(
            profileId: selectedProfileID ?? "", categoryId: nil, existing: shortcut, source: .myShortcuts)
    }

    private func openBrowseEditor(profile: ShortcutProfileData, category: ShortcutCategoryData, shortcut: ShortcutItem) {
        editorContext = ShortcutEditorContext(profileId: profile.id, categoryId: category.id, existing: shortcut, source: .category)
    }

    @ViewBuilder
    private func browseContextMenu(shortcut: ShortcutItem, bookmarked: Bool,
                                   isUser: Bool, profile: ShortcutProfileData,
                                   category: ShortcutCategoryData) -> some View {
        Button { executeShortcut(shortcut) } label: { Label("Run", systemImage: "play.fill") }
        if bookmarked {
            Button { removeFromMyShortcuts(shortcut) } label: { Label("Remove from My", systemImage: "bookmark.slash") }
        } else {
            Button { addToMyShortcuts(shortcut) } label: { Label("Add to My", systemImage: "bookmark") }
        }
        if isUser {
            Divider()
            Button { openBrowseEditor(profile: profile, category: category, shortcut: shortcut) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) { deletingShortcut = shortcut } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - Helper actions

    private func addToMyShortcuts(_ shortcut: ShortcutItem) {
        if !myShortcuts.contains(shortcut) { myShortcuts.append(shortcut) }
    }

    private func removeFromMyShortcuts(_ shortcut: ShortcutItem) {
        myShortcuts.removeAll { $0 == shortcut }
    }

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

    private func loadMyShortcuts() {
        guard let id = selectedProfileID else { myShortcuts = []; return }
        myShortcuts = profileManager.myShortcuts(for: id)
    }

    private func saveMyShortcuts() {
        guard let id = selectedProfileID else { return }
        profileManager.updateMyShortcuts(for: id, items: myShortcuts)
    }

    private func shareProfile(_ profile: ShortcutProfileData) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(profile.id).json")
        guard (try? data.write(to: tmp)) != nil else { return }
        let av = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }

    private func handleProfileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        try? profileManager.addCustomProfile(from: data)
    }

    private func handleStripImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let json = String(data: data, encoding: .utf8) else { return }
        stripManager.importProfileFromJSON(json)
    }
}


// MARK: - Preview

#Preview {
    ShortcutHubView(keyboardManager: KeyboardManager(bleManager: BLEManager()))
}
