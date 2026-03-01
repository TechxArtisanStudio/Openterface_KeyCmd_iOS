//
//  RemoteSettingsView.swift
//  KeyMod
//
//  Created on 2026/2/28.
//

import SwiftUI
import UIKit

struct RemoteSettingsView: View {

    @ObservedObject private var settings = RemoteSettings.shared
    @ObservedObject private var oauthManager = GitHubOAuthManager.shared
    @ObservedObject var sessionManager: RemoteSessionManager

    var body: some View {
        Group {
            // Show active link prominently at the top
            if sessionManager.tunnelURL != nil {
                Section {
                    if let url = sessionManager.tunnelURL {
                        RemoteLinkView(url: url)
                    }
                }
            }
            
            githubAuthSection
            repositoryConfigSection
            sessionSection
            sessionStatusSection
        }
    }

    // MARK: - GitHub Authentication

    private var githubAuthSection: some View {
        Section(header: Text("GitHub Authentication")) {
            if oauthManager.isAuthenticated {
                // User is logged in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Authenticated")
                                .fontWeight(.semibold)
                        }
                        Text("@\(oauthManager.username)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        oauthManager.logout()
                    } label: {
                        Text("Logout")
                            .font(.caption)
                    }
                }
            } else {
                // Not logged in
                VStack(spacing: 12) {
                    if let error = oauthManager.authError {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    Button(action: { oauthManager.startLogin() }) {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                            Text(oauthManager.isAuthenticating ? "Authenticating…" : "Login with GitHub")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .cornerRadius(8)
                    }
                    .disabled(oauthManager.isAuthenticating)
                    
                    Text("Login with your GitHub account to authorize this app to trigger workflows and access your repository.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Repository Configuration

    private var repositoryConfigSection: some View {
        Section(header: Text("Repository Configuration")) {
            // Repository
            HStack {
                Text("Repository")
                Spacer()
                TextField("owner/repo", text: $settings.githubRepo)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }

            // Branch
            HStack {
                Text("Branch")
                Spacer()
                TextField("main", text: $settings.githubRef)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }

            // Workflow filename
            HStack {
                Text("Workflow file")
                Spacer()
                TextField("start-server.yml", text: $settings.githubWorkflow)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Session Settings

    private var sessionSection: some View {
        Section(header: Text("Session")) {
            HStack {
                Text("Duration")
                Spacer()
                Picker("Duration", selection: $settings.sessionDurationMinutes) {
                    Text("10 min").tag(10)
                    Text("20 min").tag(20)
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                }
                .pickerStyle(.menu)
            }

            if sessionManager.state.isActive {
                Button(role: .destructive) {
                    sessionManager.stopSession()
                } label: {
                    HStack {
                        Spacer()
                        Text("Stop Session")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            } else {
                Button {
                    sessionManager.startSession()
                } label: {
                    HStack {
                        Spacer()
                        Text("Start Remote Session")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!settings.isConfigured)
            }
        }
    }

    // MARK: - Status

    private var sessionStatusSection: some View {
        Section(header: Text("Status")) {
            HStack {
                if sessionManager.state == .starting || sessionManager.state == .waitingForURL {
                    ProgressView()
                        .padding(.trailing, 6)
                }
                Text(sessionManager.state.displayText)
                    .foregroundColor(statusColor)
            }
        }
    }

    private var statusColor: Color {
        switch sessionManager.state {
        case .connected:       return .green
        case .error:           return .red
        case .idle:            return .secondary
        default:               return .primary
        }
    }
}
