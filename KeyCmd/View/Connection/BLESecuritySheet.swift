// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import SwiftUI

struct BLESecuritySheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var bondStatus: BLESecurityCommand.Status?
    @State private var showResetConfirm = false

    private var isBusy: Bool {
        switch bleManager.securityState {
        case .loading, .savingPIN, .erasing: return true
        default: return false
        }
    }

    private var hasErased: Bool { bleManager.securityState == .erased }

    private var pinError: LocalizedStringKey? {
        guard !newPIN.isEmpty || !confirmPIN.isEmpty else { return nil }
        if !BLESecurityCommand.validatePIN(newPIN) { return "PIN must be exactly 6 digits." }
        if newPIN != confirmPIN { return "PINs do not match." }
        return nil
    }

    private var canSavePIN: Bool {
        BLESecurityCommand.validatePIN(newPIN) && newPIN == confirmPIN && !isBusy
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hasErased {
                        erasedView
                    } else {
                        statusView

                        if bondStatus != nil {
                            pinSection
                            resetSection
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Pairing & Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if hasErased {
                        Button("Done") {
                            bleManager.dismissSecurityResult()
                            dismiss()
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                            .disabled(isBusy)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
        .onAppear {
            bleManager.dismissSecurityResult()
            bleManager.fetchSecurityStatus()
        }
        .onChange(of: bleManager.securityState) { state in
            switch state {
            case .ready(let status):
                bondStatus = status
            case .pinSaved:
                newPIN = ""
                confirmPIN = ""
            case .erased:
                bondStatus = nil
            default:
                break
            }
        }
        .confirmationDialog(
            "This erases all pairing records, restores the PIN to 666666, keeps one pairing slot, and restarts the device.",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Pairing", role: .destructive) { bleManager.erasePairing() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusView: some View {
        if let status = bondStatus {
            VStack(alignment: .leading, spacing: 6) {
                Text("Paired phones: \(Int(status.bondCount)) of \(Int(status.maxBonds))")
                    .font(.system(size: 15, weight: .medium))
                if status.isFull {
                    Label("Pairing slot is full", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Text("Only one phone can be paired by default. More slots can be configured over USB.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            switch bleManager.securityState {
            case .loading:
                progressRow(text: Text("Loading pairing status..."))
            case .unsupportedFirmware:
                VStack(alignment: .leading, spacing: 6) {
                    Label("This device firmware does not support pairing management.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text("Connect over USB to reset pairing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .failure(let reason):
                failureText(for: reason)
                    .font(.caption)
                    .foregroundColor(.red)
            case .idle, .ready, .savingPIN, .pinSaved, .erasing, .erased:
                EmptyView()
            }
        }

        if case .failure = bleManager.securityState {
            Button(action: { bleManager.fetchSecurityStatus() }) {
                Text("Retry")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(themeManager.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }

        if bleManager.securityState == .pinSaved {
            Label("Pairing PIN updated.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)
        }

        if bleManager.securityState == .savingPIN {
            progressRow(text: Text("Saving..."))
        }

        if bleManager.securityState == .erasing {
            progressRow(text: Text("Resetting pairing..."))
        }
    }

    @ViewBuilder
    private var pinSection: some View {
        Divider()

        VStack(alignment: .leading, spacing: 10) {
            Text("Change Pairing PIN")
                .font(.system(size: 15, weight: .bold))

            SecureField("New pairing PIN", text: $newPIN)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, design: .monospaced))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .disabled(isBusy)

            SecureField("Confirm pairing PIN", text: $confirmPIN)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, design: .monospaced))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .disabled(isBusy)

            if let pinError {
                Text(pinError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text("The PIN is used the next time a phone pairs. The current pairing stays connected.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { bleManager.setPairingPIN(newPIN) }) {
                Text("Save")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(canSavePIN ? themeManager.accentColor : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(!canSavePIN)
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Reset Pairing")
                .font(.system(size: 15, weight: .bold))

            Text("This erases all pairing records, restores the PIN to 666666, keeps one pairing slot, and restarts the device.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { showResetConfirm = true }) {
                Text("Reset Pairing and Restart")
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .foregroundColor(.red)
            .disabled(isBusy)
        }
    }

    private var erasedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pairing reset. Waiting for the device to restart...", systemImage: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.green)

            Divider()

            Text("Before pairing with another phone:")
                .font(.system(size: 14, weight: .semibold))

            Text("1. On this iPhone, open Settings > Bluetooth and choose \"Forget This Device\".")
            Text("2. On the new phone, pair the device with the factory PIN 666666.")
            Text("3. Change the pairing PIN right after pairing.")
        }
        .font(.system(size: 13))
        .foregroundColor(.secondary)
    }

    // MARK: - Helpers

    private func progressRow(text: Text) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            text.font(.system(size: 14)).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func failureText(for reason: BLEManager.SecurityFailure) -> some View {
        switch reason {
        case .notConnected:
            Text("Connect to a device first.")
        case .busy:
            Text("Another device operation is in progress. Try again shortly.")
        case .noResponse:
            Text("No response from the device. Its firmware may not support pairing management.")
        case .rejected(let status):
            HStack(spacing: 4) {
                Text("The device rejected the request.")
                Text(verbatim: String(format: "(0x%02X)", status))
            }
        case .invalidResponse:
            Text("The device returned an invalid response.")
        case .disconnected:
            Text("Disconnected before the device responded.")
        }
    }
}
