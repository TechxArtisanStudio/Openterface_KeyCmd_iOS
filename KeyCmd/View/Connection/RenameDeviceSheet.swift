// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import SwiftUI

struct RenameDeviceSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var name: String = ""

    private var byteCount: Int {
        name.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count
    }

    private var isValid: Bool { BLENameCommand.validatedNameBytes(name) != nil }

    private var isBusy: Bool {
        bleManager.renameState == .sending || bleManager.renameState == .waitingForReboot
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Device Name")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Text(verbatim: bleManager.lastConnectedDeviceName ?? "Unknown")
                            .font(.system(size: 16, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("New name")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        TextField("New name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(isBusy)
                        HStack(alignment: .top) {
                            Text("Use 1–20 UTF-8 bytes. Control characters are not allowed.")
                                .font(.caption)
                                .foregroundColor(!name.isEmpty && !isValid ? .red : .secondary)
                            Spacer()
                            Text(verbatim: "\(byteCount)/20")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(byteCount > BLENameCommand.maxNameBytes ? .red : .secondary)
                        }
                    }

                    Text("The device will restart and reconnect automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    statusView

                    Button(action: { bleManager.renameDevice(to: name) }) {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(isValid && !isBusy ? themeManager.accentColor : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(!isValid || isBusy)

                    Button(action: { bleManager.resetDeviceName() }) {
                        Text("Reset to Factory Name")
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .foregroundColor(.red)
                    .disabled(isBusy)
                }
                .padding(16)
            }
            .navigationTitle("Rename Device")
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
            bleManager.dismissRenameResult()
            name = bleManager.lastConnectedDeviceName ?? ""
        }
        .onChange(of: bleManager.renameState) { state in
            if state == .success { dismiss() }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch bleManager.renameState {
        case .sending:
            progressRow(text: Text("Renaming..."))
        case .waitingForReboot:
            progressRow(text: Text("Waiting for device to restart..."))
        case .failure(let reason):
            failureText(for: reason)
                .font(.caption)
                .foregroundColor(.red)
        case .idle, .success:
            EmptyView()
        }
    }

    private func progressRow(text: Text) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            text.font(.system(size: 14)).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func failureText(for reason: BLEManager.RenameFailure) -> some View {
        switch reason {
        case .notConnected:
            Text("Connect to a device first.")
        case .noResponse:
            Text("No response from the device. Its firmware may not support renaming.")
        case .rejected(let status):
            HStack(spacing: 4) {
                Text("The device rejected the new name.")
                Text(verbatim: String(format: "(0x%02X)", status))
            }
        case .disconnected:
            Text("Disconnected before the device confirmed the rename.")
        case .reconnectTimeout:
            Text("The device restarted but could not be found again. Please scan manually.")
        }
    }
}