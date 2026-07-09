import SwiftUI

/// Credential settings view for managing SSH profiles (matches Android CredentialSettingsFragment)
struct CredentialSettingsView: View {
    @Environment(\.dismiss) var dismiss

    @State private var profiles: [CredentialProfile] = []
    @State private var searchQuery: String = ""
    @State private var showSearch: Bool = false
    @State private var showProfileEditor: Bool = false
    @State private var editingProfile: CredentialProfile?
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
                    // Search bar
                    if showSearch {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search credentials...", text: $searchQuery)
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

                    // Profile list
                    if filteredProfiles.isEmpty && !profiles.isEmpty {
                        Text("No matching credentials")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else if profiles.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredProfiles) { profile in
                            CredentialProfileCard(
                                profile: profile,
                                onEdit: {
                                    editingProfile = profile
                                    showProfileEditor = true
                                },
                                onDelete: {
                                    deleteProfile(profile)
                                },
                                onSetActive: {
                                    credentialManager.setActiveProfileId(profile.id)
                                    loadProfiles()
                                }
                            )
                            .padding(.horizontal)
                        }
                    }

                    // Add profile button
                    Button(action: {
                        editingProfile = nil
                        showProfileEditor = true
                    }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Credential")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !showSearch {
                        Button(action: { withAnimation { showSearch = true } }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
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
        }
    }

    private func loadProfiles() {
        profiles = credentialManager.getAllProfiles()
    }

    private func deleteProfile(_ profile: CredentialProfile) {
        credentialManager.deleteProfile(id: profile.id)
        loadProfiles()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No credentials saved")
                .foregroundColor(.secondary)
            Text("Add a credential to connect to SSH endpoints.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Credential Profile Card

struct CredentialProfileCard: View {
    let profile: CredentialProfile
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSetActive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Radio button for active selection
                Button(action: onSetActive) {
                    Image(systemName: profile.isActive ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(profile.isActive ? .accentColor : .secondary)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)

                // Auth type icon
                Image(systemName: profile.authType == .sshKey ? "key.fill" : "lock.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)

                    Text(profile.shortDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Tags
                    if !profile.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(profile.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(4)
                            }
                            if profile.tags.count > 3 {
                                Text("+\(profile.tags.count - 3)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                // Edit and delete buttons
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(ThemeManager.shared.accentColor)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(profile.isActive ? Color.accentColor : Color(.systemGray4), lineWidth: 1)
        )
    }
}
