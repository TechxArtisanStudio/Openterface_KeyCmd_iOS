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
    @ObservedObject var sessionManager: RemoteSessionManager

    @State private var tokenInput: String = ""
    @State private var showToken: Bool = false
    @State private var urlCopied: Bool = false

    var body: some View {
        Group {
            githubConfigSection
            sessionSection
            sessionStatusSection
            if sessionManager.tunnelURL != nil {
                shareLinkSection
            }
        }
        .onAppear {
            tokenInput = settings.githubToken
        }
    }

    // MARK: - GitHub Configuration

    private var githubConfigSection: some View {
        Section(header: Text("GitHub Configuration"),
                footer: Text("Create a Personal Access Token with repo and workflow scopes at github.com/settings/tokens.")) {

            // Token field with show / hide toggle
            HStack {
                if showToken {
                    TextField("ghp_…", text: $tokenInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: tokenInput) { settings.githubToken = $0 }
                } else {
                    SecureField("GitHub Personal Access Token", text: $tokenInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: tokenInput) { settings.githubToken = $0 }
                }
                Button(action: { showToken.toggle() }) {
                    Image(systemName: showToken ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
            }

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

            // Branch (collapsible advanced option)
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

    // MARK: - Share Link

    private var shareLinkSection: some View {
        Section(header: Text("Share With Remote Helper"),
                footer: Text("Send this link to the person who will assist remotely. They can control the keyboard and mouse from their browser.")) {

            if let url = sessionManager.tunnelURL {
                // URL row with inline copy button
                HStack(spacing: 8) {
                    Text(url.absoluteString)
                        .font(.footnote)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        copyURL(url)
                    } label: {
                        Image(systemName: urlCopied ? "checkmark" : "doc.on.doc")
                            .font(.body)
                            .foregroundColor(urlCopied ? .green : .accentColor)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .animation(.easeInOut(duration: 0.2), value: urlCopied)
                }

                if urlCopied {
                    Text("Copied to clipboard!")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }

                Button {
                    presentShareSheet(url: url)
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Link…")
                    }
                }
            }
        }
    }

    // MARK: - Copy helper

    private func copyURL(_ url: URL) {
        UIPasteboard.general.url = url
        withAnimation { urlCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { self.urlCopied = false }
        }
    }

    // MARK: - Share Sheet

    private func presentShareSheet(url: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        // Find the top-most presented view controller to present on
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        // iPad needs a sourceView / barButtonItem for the popover
        activityVC.popoverPresentationController?.sourceView = topVC.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(
            x: topVC.view.bounds.midX,
            y: topVC.view.bounds.midY,
            width: 0, height: 0
        )
        topVC.present(activityVC, animated: true)
    }
}
