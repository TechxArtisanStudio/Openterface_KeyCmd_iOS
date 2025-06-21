//
//  ContentView.swift
//  KeyMod
//
//  Created by 彭志坚 on 2025/6/19.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    let keys: [[String]] = [
        ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "0", "-", "="],
        ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]"],
        ["Caps", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Enter"],
        ["Shift", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "Shift"],
        ["Ctrl", "Alt", "Space", "Alt", "Ctrl"]
    ]

    @StateObject private var bleManager = BLEManager()
    @State private var showPopup = false
    @State private var previousPosition: CGPoint? = nil  // Add this line

    var body: some View {
        VStack(spacing: 0) {
            // Top menu with Bluetooth button
            HStack {
                Text("Openterface KeyMod")
                    .font(.title)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {
                    if bleManager.checkBluetoothPermission() {
                        bleManager.startScanning()
                        showPopup = true
                        print("Scanning for Bluetooth devices...")
                    } else {
                        print("Bluetooth permission not granted")
                    }
                }) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.2))

            // Mouse touch pad area
            VStack(spacing: 0) {
                Rectangle()
                    .frame(maxHeight: .infinity)
                    .foregroundColor(Color.gray.opacity(0.3))
                    .cornerRadius(10)
                    .overlay(
                        Text("Touch Pad")
                            .font(.headline)
                            .foregroundColor(.black)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Store current position to calculate delta on next update
                                let currentPosition = value.location
                                
                                // Get delta movement since last update
                                var xDelta = Int(currentPosition.x - (previousPosition?.x ?? currentPosition.x))
                                var yDelta = Int(currentPosition.y - (previousPosition?.y ?? currentPosition.y))
                                
                                // Update previous position for next calculation
                                previousPosition = currentPosition
                                
                                let mousePressed = 0x00 // Don't pressed
                                let wheelMove = 0x00 // No wheel movement
                                
                                xDelta *= 4
                                yDelta *= 4
                                
                                // Limit delta to reasonable range before encoding
                                let boundedXDelta = max(-127, min(127, xDelta))
                                let boundedYDelta = max(-127, min(127, yDelta))

                                // Convert bounded delta movements to protocol values
                                let xDirection = boundedXDelta >= 0 ? boundedXDelta : ( 0x100 + boundedXDelta)
                                let yDirection = boundedYDelta >= 0 ? boundedYDelta : ( 0x100 + boundedYDelta)

                                // Construct the data packet
                                var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), UInt8(xDirection), UInt8(yDirection), UInt8(wheelMove)]
                                let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
                                dataPacket.append(UInt8(sum))

                                // Send the data packet to BLE
                                bleManager.sendTouchData(data: Data(dataPacket))
                                print("Delt                                                                                                                                                                a moved x: \(xDelta) y: \(yDelta)")
                            }
                             .onEnded { value in
                                 // Reset previous position when gesture ends
                                 previousPosition = nil
                                
                                 let mouseReleased = 0x00 // Simulate mouse released
                                 let dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00, 0x63] // Example sum for released state
                                 bleManager.sendTouchData(data: Data(dataPacket))
                                 print("Touch ended at: \(value.location), \nData sent: \(dataPacket.map { String(format: "%02X", $0) }.joined(separator: " "))")
                             }
                    )

                // Keyboard layout
                VStack(spacing: 0) {
                    ForEach(keys, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(row, id: \.self) { key in
                                Button(action: {
                                    print("\(key) pressed")
                                }) {
                                    Text(key)
                                        .font(.system(size: 12)) 
                                        .frame(maxWidth: .infinity, maxHeight: 50)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(5)
                                        .foregroundColor(Color.primary) // Automatically adapts to light/dark mode
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.05))
        .sheet(isPresented: $showPopup) {
            List(bleManager.discoveredDevices, id: \.0.identifier) { device, rssi in
                VStack(alignment: .leading) {
                    Text(device.name ?? "Unknown Device")
                        .font(.headline)
                        .foregroundColor(bleManager.connectedDevices.contains(device.identifier) ? .green : .primary)
                    Text("RSSI: \(rssi.stringValue)")
                        .font(.footnote)
                        .foregroundColor(.blue)
                    Text("UUID: \(device.identifier.uuidString)")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                .onTapGesture {
                    bleManager.connectToDevice(device)
                }
            }
        }
        .onAppear {
            // Pass the binding of showPopup to BLEManager.
            bleManager.showPopupBinding = $showPopup
        }
    }
}

#Preview {
    ContentView()
}
