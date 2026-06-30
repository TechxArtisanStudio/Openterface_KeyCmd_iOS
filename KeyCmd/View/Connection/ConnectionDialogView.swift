import SwiftUI

// ponytail: mirrors Android's dialog_connection.xml - status header + BT card + auto-connect
struct ConnectionDialogView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var showScanner = false

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

                // Status
                Text(statusText)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                    rssi: bleManager.currentRSSI,
                    themeManager: themeManager
                )
                .onTapGesture { showScanner = true }
                .padding(.horizontal, 16)
                .padding(.top, 8)

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

                Spacer()
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
    }

    private var statusText: String {
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
    let rssi: NSNumber?
    @ObservedObject var themeManager: ThemeManager

    private var isConnected: Bool { connectionState == .connected }
    private var isConnecting: Bool { connectionState == .connecting || connectionState == .reconnecting }

    private var iconName: String {
        switch connectionState {
        case .connected: return "bluetooth.connected"
        case .connecting, .reconnecting: return "antenna.radiowaves.left.and.right"
        case .disconnected: return "bluetooth"
        }
    }

    private var statusText: String {
        switch connectionState {
        case .connected: return deviceName ?? "Connected"
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

                Text(statusText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
