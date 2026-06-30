import SwiftUI
import CoreBluetooth

// ponytail: mirrors Android's activity_bluetooth.xml - scan button + device list
struct BluetoothScannerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var themeManager = ThemeManager.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Scan button
                Button(action: {
                    bleManager.discoveredDevices.removeAll()
                    bleManager.startScanning()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan for Devices")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(themeManager.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding()

                Divider()

                // Device list
                List {
                    if bleManager.discoveredDevices.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("No devices found")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Make sure your Openterface device is powered on")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(bleManager.discoveredDevices, id: \.0.identifier) { peripheral, rssi in
                            DeviceRow(
                                peripheral: peripheral,
                                rssi: rssi,
                                isConnected: bleManager.connectedDevices.contains(peripheral.identifier),
                                onTap: {
                                    bleManager.connectToDevice(peripheral)
                                    dismiss()
                                }
                            )
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Bluetooth Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct DeviceRow: View {
    let peripheral: CBPeripheral
    let rssi: NSNumber
    let isConnected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20))
                    .foregroundColor(isConnected ? .green : .secondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(peripheral.name ?? "Unknown Device")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)

                        if isConnected {
                            Text("CONNECTED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 4) {
                        SignalStrengthView(rssi: rssi)
                        Text("RSSI: \(rssi.intValue)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !isConnected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
