import SwiftUI

/// SSH connection dialog with profile cards, search, and add/manage.
struct ConnectionDialog: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TerminalViewModel

    @State private var profiles: [CredentialProfile] = []
    @State private var selectedProfileId: String?
    @State private var searchQuery: String = ""
    @State private var showSearch: Bool = false
    @State private var showProfileEditor: Bool = false
    @State private var editingProfile: CredentialProfile?
    @State private var showDeviceInfo: CredentialProfile?
    @FocusState private var searchFocused: Bool

    private let credentialManager = CredentialManager.shared

    var filteredProfiles: [CredentialProfile] {
        if searchQuery.isEmpty { return profiles }
        let q = searchQuery.lowercased()
        return profiles.filter {
            $0.displayLabel.lowercased().contains(q)
            || $0.shortDescription.lowercased().contains(q)
            || $0.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title area
                    if !showSearch {
                        HStack {
                            Image(systemName: "terminal")
                                .foregroundColor(.accentColor)
                                .font(.title3)
                            Text("Connect")
                                .font(.title3.bold())
                            Spacer()
                            Button(action: { withAnimation { showSearch = true } }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Search bar
                    if showSearch {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search devices...", text: $searchQuery)
                                .focused($searchFocused)
                                .autocorrectionDisabled()
                            if !searchQuery.isEmpty {
                                Button(action: { searchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                            Button("Cancel") {
                                withAnimation {
                                    showSearch = false
                                    searchQuery = ""
                                }
                                searchFocused = false
                            }
                            .font(.subheadline)
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .onAppear { searchFocused = true }
                    }

                    // Transport label (BLE only)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRANSPORT")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack {
                            TransportBadge(label: "BLE", icon: "antenna.radiowaves.left.and.right", isSelected: true)
                        }
                    }
                    .padding(.horizontal)

                    // Device list label
                    Text("DEVICES")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    // Profile cards
                    if filteredProfiles.isEmpty && !profiles.isEmpty {
                        Text("No matching devices")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else if profiles.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredProfiles) { profile in
                            ProfileCard(
                                profile: profile,
                                isSelected: profile.id == selectedProfileId
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedProfileId = profile.id
                                }
                            }
                            .contextMenu {
                                Button(action: { editingProfile = profile; showProfileEditor = true }) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(action: { showDeviceInfo = profile }) {
                                    Label("Details", systemImage: "info.circle")
                                }
                                Button(role: .destructive, action: { deleteProfile(profile) }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Add profile button
                    Button(action: { editingProfile = nil; showProfileEditor = true }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Profile")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)

                    // Error display
                    if case .error(let msg) = viewModel.connectionStatus {
                        Text(msg)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { connectSelected() }
                        .disabled(selectedProfileId == nil || viewModel.connectionStatus == .connecting)
                }
            }
            .onAppear { loadProfiles() }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorSheet(
                    profile: editingProfile,
                    onSave: { profile, password in
                        if editingProfile != nil {
                            credentialManager.updateProfile(profile, password: password.isEmpty ? nil : password)
                        } else {
                            credentialManager.addProfile(profile, password: password)
                        }
                        loadProfiles()
                    }
                )
            }
            .sheet(item: $showDeviceInfo) { profile in
                DeviceInfoSheet(profile: profile) {
                    editingProfile = profile
                    showProfileEditor = true
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No saved devices")
                .foregroundColor(.secondary)
            Text("Add a profile to connect to an SSH endpoint.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func loadProfiles() {
        profiles = credentialManager.getAllProfiles()
        if selectedProfileId == nil {
            selectedProfileId = credentialManager.getActiveProfile()?.id
        }
    }

    private func connectSelected() {
        guard let id = selectedProfileId,
              let profile = credentialManager.getProfile(id: id) else { return }
        let password = credentialManager.getPassword(for: id)
        credentialManager.setActiveProfileId(id)
        dismiss()
        Task {
            await viewModel.connect(
                host: profile.host,
                port: profile.port,
                username: profile.username,
                password: password
            )
        }
    }

    private func deleteProfile(_ profile: CredentialProfile) {
        credentialManager.deleteProfile(id: profile.id)
        loadProfiles()
        if selectedProfileId == profile.id {
            selectedProfileId = credentialManager.getActiveProfile()?.id
        }
    }
}

// MARK: - Subviews

private struct TransportBadge: View {
    let label: String
    let icon: String
    let isSelected: Bool
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundColor(isSelected ? Color.accentColor : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .opacity(enabled ? 1 : 0.4)
    }
}

private struct ProfileCard: View {
    let profile: CredentialProfile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Radio indicator
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 2)
                    .frame(width: 20, height: 20)
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayLabel)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(profile.shortDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Profile Editor Sheet

struct ProfileEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    let profile: CredentialProfile?
    let onSave: (CredentialProfile, String) -> Void

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var notes: String = ""
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var showTagSelector: Bool = false

    private let credentialManager = CredentialManager.shared

    var isEditing: Bool { profile != nil }

    var body: some View {
        NavigationView {
            Form {
                Section("Profile") {
                    TextField("Name (optional)", text: $name)
                        .autocorrectionDisabled()
                }

                Section("Server") {
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }

                Section("Authentication") {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                Section("Tags") {
                    // Tag input field
                    HStack {
                        TextField("Add tag...", text: $tagInput)
                            .autocorrectionDisabled()
                            .onSubmit {
                                addTag()
                            }
                        Button(action: { showTagSelector = true }) {
                            Image(systemName: "tag")
                                .foregroundColor(.accentColor)
                        }
                    }

                    // Display current tags
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.caption)
                                        Button(action: { removeTag(tag) }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    } else {
                        Text("No tags added")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Profile" : "New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(host.isEmpty || username.isEmpty)
                }
            }
            .onAppear {
                if let p = profile {
                    name = p.name
                    host = p.host
                    port = String(p.port)
                    username = p.username
                    password = CredentialManager.shared.getPassword(for: p.id)
                    notes = p.notes
                    tags = p.tags
                } else {
                    // Default host for new profiles
                    host = "192.168.11.2"
                }
            }
            .sheet(isPresented: $showTagSelector) {
                TagSelectorView(selectedTags: $tags)
            }
        }
    }

    private func save() {
        var p = profile ?? CredentialProfile()
        p.name = name
        p.host = host
        p.port = Int(port) ?? 22
        p.username = username
        p.notes = notes
        p.tags = tags
        onSave(p, password)
        dismiss()
    }

    private func addTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty && !tags.contains(tag) {
            tags.append(tag)
            tagInput = ""
        }
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

// MARK: - Device Info Sheet

private struct DeviceInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    let profile: CredentialProfile
    let onEdit: () -> Void

    var body: some View {
        NavigationView {
            List {
                Section {
                    InfoRow(label: "Name", value: profile.displayLabel)
                    InfoRow(label: "Host", value: profile.host)
                    InfoRow(label: "Port", value: String(profile.port))
                    InfoRow(label: "Username", value: profile.username)
                    InfoRow(label: "Auth", value: profile.authType.rawValue)
                }

                if !profile.tags.isEmpty {
                    Section("Tags") {
                        Text(profile.tags.joined(separator: ", "))
                    }
                }

                if !profile.notes.isEmpty {
                    Section("Notes") {
                        Text(profile.notes)
                    }
                }

                Section("Metadata") {
                    InfoRow(label: "Created", value: formatDate(profile.createdAt))
                    InfoRow(label: "Updated", value: formatDate(profile.updatedAt))
                }
            }
            .navigationTitle("Device Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        dismiss()
                        onEdit()
                    }
                }
            }
        }
    }

    private func formatDate(_ interval: TimeInterval) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: Date(timeIntervalSince1970: interval))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Tag Selector View

struct TagSelectorView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedTags: [String]
    @State private var newTag: String = ""

    private let credentialManager = CredentialManager.shared

    var allTags: [String] {
        credentialManager.getAllTags()
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        TextField("New tag...", text: $newTag)
                            .autocorrectionDisabled()
                        Button("Add") {
                            let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !tag.isEmpty && !selectedTags.contains(tag) {
                                selectedTags.append(tag)
                                newTag = ""
                            }
                        }
                        .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Existing Tags") {
                    if allTags.isEmpty {
                        Text("No tags yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(allTags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                if selectedTags.contains(tag) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedTags.contains(tag) {
                                    selectedTags.removeAll { $0 == tag }
                                } else {
                                    selectedTags.append(tag)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
