// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import SwiftUI

// ponytail: mirrors Android's dialog_connection.xml - status header + BT card + auto-connect
struct ConnectionDialogView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var showScanner = false
    @State private var showRename = false
    @State private var showECMIP = false
    @State private var showSecurity = false

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.36)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Connection")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        // Status
                        Text(statusText)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let issue = bleManager.pairingIssue {
                            pairingIssueCard(issue)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        if bleManager.showFactoryPINReminder {
                            factoryPINBanner
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        // Connection type label
                        Text("Connection Type")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Bluetooth card
                        BluetoothCard(
                            connectionState: bleManager.connectionState,
                            deviceName: bleManager.lastConnectedDeviceName,
                            isWaitingForPairing: bleManager.isWaitingForPairing,
                            rssi: bleManager.currentRSSI,
                            themeManager: themeManager
                        )
                        .onTapGesture {
                            if bleManager.connectionState == .connected {
                                bleManager.disconnectCurrentDevice()
                            } else {
                                showScanner = true
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Rename entry (connected devices only)
                        if bleManager.connectionState == .connected {
                            Button(action: { showRename = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 13))
                                    Text("Rename Device")
                                        .font(.system(size: 14))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .foregroundColor(themeManager.accentColor)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }

                            Button(action: { showECMIP = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "network")
                                        .font(.system(size: 13))
                                    Text("ECM Network")
                                        .font(.system(size: 14))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .foregroundColor(themeManager.accentColor)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }

                            Button(action: { showSecurity = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.shield")
                                        .font(.system(size: 13))
                                    Text("Pairing & Security")
                                        .font(.system(size: 14))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .foregroundColor(themeManager.accentColor)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                        }

                        // Auto-connect toggle
                        Toggle(isOn: Binding(
                            get: { bleManager.autoConnectEnabled },
                            set: { bleManager.autoConnectEnabled = $0 }
                        )) {
                            Text("Auto-connect on startup")
                                .font(.system(size: 14))
                        }
                        .tint(themeManager.accentColor)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        // Last connected info
                        if let lastDevice = bleManager.lastConnectedDeviceName {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("Last connected: \(lastDevice)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: 520)
            }
            .frame(maxWidth: 400)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showScanner) {
            BluetoothScannerView(bleManager: bleManager)
        }
        .sheet(isPresented: $showRename) {
            RenameDeviceSheet(bleManager: bleManager)
        }
        .sheet(isPresented: $showECMIP) {
            ECMIPSheet(bleManager: bleManager)
        }
        .sheet(isPresented: $showSecurity) {
            BLESecuritySheet(bleManager: bleManager)
        }
    }

    private func pairingIssueCard(_ issue: BLEManager.PairingIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pairing failed")
                    .font(.system(size: 13, weight: .semibold))
                Text(pairingIssueHint(issue))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: { bleManager.dismissPairingIssue() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
    }

    private func pairingIssueHint(_ issue: BLEManager.PairingIssue) -> LocalizedStringKey {
        switch issue {
        case .authenticationFailed:
            return "The pairing code was rejected or the prompt was cancelled. Tap the Bluetooth card to try again."
        case .staleBond:
            return "The device may already be paired with another phone. Go to Settings > Bluetooth, tap the device, and choose \"Forget This Device\"."
        case .timeout:
            return "Pairing timed out. Tap the Bluetooth card to try again."
        case .connectionFailed:
            return "Could not start pairing. Move closer to the device and try again."
        }
    }

    private var factoryPINBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 15))
                .foregroundColor(themeManager.accentColor)

            Text("This device may still use the factory PIN 666666. Change it to keep others out.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button("Change") { showSecurity = true }
                .font(.caption.bold())

            Button(action: { bleManager.dismissFactoryPINReminder() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(10)
    }

    private var statusText: LocalizedStringKey {
        if bleManager.isWaitingForPairing { return "Waiting for pairing..." }
        switch bleManager.connectionState {
        case .connected:
            if let name = bleManager.lastConnectedDeviceName {
                return "Connected to \(name)"
            }
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .disconnected:
            return "Disconnected"
        }
    }
}

private struct BluetoothCard: View {
    let connectionState: BLEManager.ConnectionState
    let deviceName: String?
    let isWaitingForPairing: Bool
    let rssi: NSNumber?
    @ObservedObject var themeManager: ThemeManager

    private var isConnected: Bool { connectionState == .connected }
    private var isConnecting: Bool { connectionState == .connecting || connectionState == .reconnecting }

    private var iconName: String {
        if isWaitingForPairing { return "lock.fill" }
        switch connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .reconnecting: return "antenna.radiowaves.left.and.right"
        case .disconnected: return "antenna.radiowaves.left.and.right"
        }
    }

    private var statusText: LocalizedStringKey {
        if isWaitingForPairing { return "Waiting for pairing..." }
        switch connectionState {
        case .connected: return LocalizedStringKey(deviceName ?? "Connected")
        case .connecting: return "Connecting..."
        case .reconnecting: return "Reconnecting..."
        case .disconnected: return "Not connected"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bluetooth")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    if isConnected, let rssiValue = rssi?.doubleValue {
                        // ponytail: show nRF Connect-style signal data
                        let distanceMeters = pow(10.0, (-59.0 - rssiValue) / 20.0)
                        let distanceStr = distanceMeters < 1.0 ? "\(Int(distanceMeters * 100))cm" : String(format: "%.1fm", distanceMeters)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("\(Int(rssiValue)) dBm · \(distanceStr)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                if isWaitingForPairing {
                    Text("Enter the 6-digit PIN in the iOS prompt (factory default 666666).")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if isConnected {
                SignalStrengthView(rssi: rssi)
            }

            Image(systemName: iconName)
                .font(.system(size: 22))
                .foregroundColor(isConnected ? themeManager.accentColor : .secondary)
                .rotationEffect(.degrees(isConnecting ? 0 : 0))
                .opacity(isConnecting ? 0.5 : 1.0)
                .animation(isConnecting ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isConnecting)
        }
        .padding(14)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isConnected ? themeManager.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
    }
}
