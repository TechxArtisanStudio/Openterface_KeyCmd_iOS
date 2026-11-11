// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import SwiftUI

struct ECMIPSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var hostIP = ""
    @State private var devIP = ""
    @State private var subnetMask = ""
    @State private var targetHostIP = ""
    @State private var targetDevIP = ""
    @State private var hasLoaded = false
    @State private var showResetConfirm = false

    private var isBusy: Bool {
        bleManager.ecmIPState == .fetching || bleManager.ecmIPState == .saving
    }

    private var editedConfig: ECMIPCommand.Config? {
        guard let host = ECMIPCommand.parseIPv4(hostIP),
              let dev = ECMIPCommand.parseIPv4(devIP),
              let mask = ECMIPCommand.parseIPv4(subnetMask),
              let targetHost = ECMIPCommand.parseIPv4(targetHostIP),
              let targetDev = ECMIPCommand.parseIPv4(targetDevIP) else { return nil }
        return ECMIPCommand.Config(
            hostIP: host, devIP: dev, subnetMask: mask,
            targetHostIP: targetHost, targetDevIP: targetDev
        )
    }

    private var isValid: Bool {
        guard let config = editedConfig else { return false }
        return ECMIPCommand.validate(config)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Changes take effect immediately. The network reconnects briefly.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if hasLoaded {
                        ipField("Host IP", caption: "IP address of the host (Mac/PC).", text: $hostIP)
                        ipField("Device Host IP", caption: "IP address of the device on the host side.", text: $devIP)
                        ipField("Subnet Mask", caption: "Subnet mask shared by all addresses.", text: $subnetMask)
                        ipField("Target IP", caption: "IP address of the target PC.", text: $targetHostIP)
                        ipField("Device Target IP", caption: "IP address of the device on the target side.", text: $targetDevIP)

                        if !isValid {
                            Text("Enter valid IPv4 addresses. All four IPs must be in the same subnet and different from each other.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    statusView

                    if hasLoaded {
                        Button(action: { if let config = editedConfig { bleManager.saveECMIP(config) } }) {
                            Text("Save")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(isValid && !isBusy ? themeManager.accentColor : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(!isValid || isBusy)

                        Button(action: { showResetConfirm = true }) {
                            Text("Reset to Defaults")
                                .font(.system(size: 15))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .foregroundColor(.red)
                        .disabled(isBusy)
                    } else if case .failure = bleManager.ecmIPState {
                        Button(action: { bleManager.fetchECMIP() }) {
                            Text("Retry")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(themeManager.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("ECM Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isBusy)
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
        .onAppear {
            bleManager.dismissECMIPResult()
            if !hasLoaded { bleManager.fetchECMIP() }
        }
        .onChange(of: bleManager.ecmIPState) { state in
            if case .fetched(let config) = state {
                hostIP = ECMIPCommand.formatIPv4(config.hostIP)
                devIP = ECMIPCommand.formatIPv4(config.devIP)
                subnetMask = ECMIPCommand.formatIPv4(config.subnetMask)
                targetHostIP = ECMIPCommand.formatIPv4(config.targetHostIP)
                targetDevIP = ECMIPCommand.formatIPv4(config.targetDevIP)
                hasLoaded = true
            }
        }
        .confirmationDialog(
            "Reset ECM network settings to factory defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { bleManager.resetECMIP() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch bleManager.ecmIPState {
        case .fetching:
            progressRow(text: Text("Loading configuration..."))
        case .saving:
            progressRow(text: Text("Saving..."))
        case .failure(let reason):
            failureText(for: reason)
                .font(.caption)
                .foregroundColor(.red)
        case .idle, .fetched:
            EmptyView()
        }
    }

    private func progressRow(text: Text) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            text.font(.system(size: 14)).foregroundColor(.secondary)
        }
    }

    private func ipField(_ title: LocalizedStringKey, caption: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, design: .monospaced))
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(isBusy)
            Text(caption)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func failureText(for reason: BLEManager.ECMIPFailure) -> some View {
        switch reason {
        case .notConnected:
            Text("Connect to a device first.")
        case .busy:
            Text("Another device operation is in progress. Try again shortly.")
        case .noResponse:
            Text("No response from the device. Its firmware may not support ECM IP configuration.")
        case .rejected(let status):
            HStack(spacing: 4) {
                Text("The device rejected the configuration.")
                Text(verbatim: String(format: "(0x%02X)", status))
            }
        case .invalidResponse:
            Text("The device returned an invalid response.")
        case .disconnected:
            Text("Disconnected before the device responded.")
        }
    }
}