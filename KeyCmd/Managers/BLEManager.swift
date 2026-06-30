import CoreBluetooth
import Combine
import SwiftUI

final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // MARK: - Connection State

    enum ConnectionState {
        case disconnected, connecting, connected, reconnecting
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastConnectedUUID = "ble_last_connected_uuid"
        static let lastConnectedName = "ble_last_connected_name"
        static let autoConnectEnabled = "ble_auto_connect_enabled"
    }

    // MARK: - Published State

    @Published var discoveredDevices: [(CBPeripheral, NSNumber)] = []
    @Published var connectedDevices: Set<UUID> = []
    @Published var currentRSSI: NSNumber? = nil
    @Published var connectionState: ConnectionState = .disconnected
    @Published var isReconnecting: Bool = false
    @Published var lastConnectedDeviceName: String?

    // ponytail: mirrors Android's auto-connect checkbox
    var autoConnectEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoConnectEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoConnectEnabled) }
    }

    // MARK: - Private State

    private var centralManager: CBCentralManager!
    private let logger = LogManager.shared

    private var connectedPeripheral: CBPeripheral?
    private var fff2Characteristic: CBCharacteristic?
    private var fff1Characteristic: CBCharacteristic?

    // ponytail: simple exponential backoff, capped at 3 retries (Android uses 1 with 5s delay)
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts = 3
    private var reconnectWorkItem: DispatchWorkItem?
    private var rssiTimer: Timer?

    /// Raw data publish/subscribe for BLE-Eth transport (bypasses HID parsing).
    let rawDataSubject = PassthroughSubject<Data, Never>()

    var showPopupBinding: Binding<Bool>?

    // MARK: - Init

    override init() {
        super.init()
        lastConnectedDeviceName = UserDefaults.standard.string(forKey: Keys.lastConnectedName)
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.log("Bluetooth is powered on", category: "BLE", level: .success)
            // ponytail: silent reconnect to last known device without scanning
            if autoConnectEnabled {
                restoreLastConnectedDevice()
            }
        case .poweredOff:
            logger.log("Bluetooth is powered off", category: "BLE", level: .warning)
            connectionState = .disconnected
        case .unsupported:
            logger.log("Bluetooth is unsupported", category: "BLE", level: .error)
        case .unauthorized:
            logger.log("Bluetooth permission not granted", category: "BLE", level: .error)
        default:
            logger.log("Bluetooth state is unknown", category: "BLE", level: .warning)
        }
    }

    // MARK: - Auto-Restore Last Device

    private func restoreLastConnectedDevice() {
        guard let uuidString = UserDefaults.standard.string(forKey: Keys.lastConnectedUUID),
              let uuid = UUID(uuidString: uuidString) else { return }

        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = peripherals.first {
            logger.log("Auto-restoring connection to \(peripheral.name ?? "Unknown")", category: "BLE")
            connectionState = .connecting
            isReconnecting = true
            centralManager.connect(peripheral, options: nil)
        }
    }

    func checkBluetoothPermission() -> Bool {
        centralManager.state == .poweredOn
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check peripheral.name first, then fall back to advertisement local name
        // (some devices like KVM-Go don't populate peripheral.name until connected)
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let deviceName = (peripheral.name ?? advName)?.lowercased() ?? ""
        if !deviceName.isEmpty, (deviceName.hasPrefix("openterface") || deviceName.hasPrefix("kvm") || deviceName.hasPrefix("keymod")) {
            logger.log("Discovered device: \(peripheral.name ?? advName ?? "Unknown")", category: "BLE")
            logger.log("RSSI\(RSSI)", category: "BLE")
            if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                logger.log("Service UUIDs from advertisement: \(serviceUUIDs)", category: "BLE")
            }
            peripheral.delegate = self
            connectionState = .connecting
            centralManager.connect(peripheral, options: nil)
            discoveredDevices.append((peripheral, RSSI))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.log("Connected to \(peripheral.name ?? "Unknown")", category: "BLE", level: .success)
        connectedPeripheral = peripheral
        connectedDevices.insert(peripheral.identifier)
        connectionState = .connected
        isReconnecting = false
        reconnectAttempts = 0
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        peripheral.discoverServices(nil)
        startRSSIMonitoring()

        // Persist last connected device for auto-reconnect
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Keys.lastConnectedUUID)
        let deviceName = peripheral.name ?? "Unknown"
        UserDefaults.standard.set(deviceName, forKey: Keys.lastConnectedName)
        DispatchQueue.main.async {
            self.lastConnectedDeviceName = deviceName
            self.showPopupBinding?.wrappedValue = false
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.log("Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "Unknown error")", category: "BLE", level: .error)
        connectionState = .disconnected
        isReconnecting = false
        scheduleReconnect(for: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logger.log("Error discovering services: \(error.localizedDescription)", category: "BLE", level: .error)
            return
        }

        guard let services = peripheral.services else {
            logger.log("No services found", category: "BLE", level: .warning)
            return
        }

        for service in services {
            logger.log("Service UUID: \(service.uuid)", category: "BLE")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            logger.log("Error discovering characteristics: \(error.localizedDescription)", category: "BLE", level: .error)
            return
        }

        guard let characteristics = service.characteristics else {
            logger.log("No characteristics found for service \(service.uuid)", category: "BLE", level: .warning)
            return
        }

        logger.log("Characteristics for service \(service.uuid):", category: "BLE")
        for characteristic in characteristics {
            logger.log("Characteristic UUID: \(characteristic.uuid)", category: "BLE")
            if characteristic.uuid == CBUUID(string: "FFF2") {
                fff2Characteristic = characteristic
                logger.log("FFF2 characteristic found!", category: "BLE", level: .success)
            }
            if characteristic.uuid == CBUUID(string: "FFF1") {
                fff1Characteristic = characteristic
                logger.log("FFF1 characteristic found!", category: "BLE", level: .success)
                // Enable notifications for incoming BLE-Eth data
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                    logger.log("FFF1 notifications enabled", category: "BLE", level: .success)
                }
            }
        }
    }

    func connectToDevice(_ peripheral: CBPeripheral) {
        logger.log("Connecting to \(peripheral.name ?? "Unknown")", category: "BLE")
        connectionState = .connecting
        cancelReconnect()
        centralManager.connect(peripheral, options: nil)
    }

    func disconnectDevice(_ peripheral: CBPeripheral) {
        logger.log("Disconnecting from device", category: "BLE")
        cancelReconnect()
        // Clear persisted last device (user explicitly disconnected)
        UserDefaults.standard.removeObject(forKey: Keys.lastConnectedUUID)
        UserDefaults.standard.removeObject(forKey: Keys.lastConnectedName)
        DispatchQueue.main.async {
            self.lastConnectedDeviceName = nil
        }
        connectionState = .disconnected
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func startScanning() {
        if centralManager.state == .poweredOn {
            logger.log("Starting BLE scan", category: "BLE")
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            logger.log("Cannot start scanning, Bluetooth is not powered on", category: "BLE", level: .warning)
        }
    }

    func sendData(to peripheral: CBPeripheral, data: Data, characteristic: CBCharacteristic) {
        guard characteristic.properties.contains(.write) else {
            logger.log("Characteristic does not support writing", category: "BLE", level: .error)
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.logHex(hexString, message: "Data sent", category: "BLE")
    }

    func sendTouchData(data: Data) {
        guard let connectedPeripheral = connectedPeripheral else {
            logger.log("No connected peripheral", category: "BLE", level: .error)
            return
        }

        guard let fff2Characteristic = fff2Characteristic else {
            logger.log("FFF2 characteristic not found", category: "BLE", level: .error)
            return
        }

        guard fff2Characteristic.properties.contains(.write) else {
            logger.log("FFF2 characteristic does not support writing", category: "BLE", level: .error)
            return
        }

        connectedPeripheral.writeValue(data, for: fff2Characteristic, type: .withoutResponse)
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.logHex(hexString, message: "TX: ", category: "BLE")
    }

    /// Send raw bytes to the device (for BLE-Eth transport).
    /// Mirrors sendTouchData but semantically distinct — used for arbitrary protocol bytes.
    func sendRawData(_ data: Data) {
        guard let connectedPeripheral = connectedPeripheral else {
            logger.log("No connected peripheral", category: "BLE", level: .error)
            return
        }

        guard let fff2Characteristic = fff2Characteristic else {
            logger.log("FFF2 characteristic not found", category: "BLE", level: .error)
            return
        }

        guard fff2Characteristic.properties.contains(.writeWithoutResponse) else {
            logger.log("FFF2 characteristic does not support writeWithoutResponse", category: "BLE", level: .error)
            return
        }

        connectedPeripheral.writeValue(data, for: fff2Characteristic, type: .withoutResponse)
    }

    /// BLE peripheral delegate callback for characteristic value updates (notifications).
    /// Routes incoming raw data to rawDataSubject for BLE-Eth transport.
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.log("Error updating value for characteristic: \(error.localizedDescription)", category: "BLE", level: .error)
            return
        }

        guard let data = characteristic.value else { return }

        if characteristic.uuid == CBUUID(string: "FFF1") {
            // Raw data from BLE-Eth tunnel — publish to subscribers
            rawDataSubject.send(data)
        }
    }

    func sendMouseMove(dx: Int, dy: Int) {
        var dx8 = Int8(clamping: dx)
        var dy8 = Int8(clamping: dy)
        let data = Data(bytes: &dx8, count: 1) + Data(bytes: &dy8, count: 1)
        sendTouchData(data: data)
    }

    private func startRSSIMonitoring() {
        guard let peripheral = connectedPeripheral else { return }

        rssiTimer?.invalidate()
        peripheral.readRSSI()

        // ponytail: weak self to prevent retain cycle; stored timer so it can be invalidated
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  self.connectedPeripheral != nil,
                  self.connectedDevices.contains(peripheral.identifier) else { return }
            peripheral.readRSSI()
        }
    }

    private func stopRSSIMonitoring() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error = error {
            logger.log("Error reading RSSI: \(error.localizedDescription)", category: "BLE", level: .error)
            return
        }

        DispatchQueue.main.async {
            self.currentRSSI = RSSI
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.log("Disconnected from \(peripheral.name ?? "Unknown")", category: "BLE", level: .warning)
        connectedDevices.remove(peripheral.identifier)
        stopRSSIMonitoring()

        if peripheral.identifier == connectedPeripheral?.identifier {
            connectedPeripheral = nil
            fff2Characteristic = nil
            fff1Characteristic = nil
            currentRSSI = nil
        }

        // ponytail: auto-reconnect on unexpected disconnect (error != nil means not user-initiated)
        if error != nil && autoConnectEnabled {
            connectionState = .reconnecting
            scheduleReconnect(for: peripheral)
        } else {
            connectionState = .disconnected
        }
    }

    // MARK: - Reconnect Logic

    private func scheduleReconnect(for peripheral: CBPeripheral) {
        guard reconnectAttempts < maxReconnectAttempts else {
            logger.log("Max reconnect attempts reached, giving up", category: "BLE", level: .warning)
            connectionState = .disconnected
            isReconnecting = false
            return
        }

        cancelReconnect()
        reconnectAttempts += 1
        isReconnecting = true

        // ponytail: exponential backoff 1s, 2s, 4s (Android uses fixed 5s)
        let delay = pow(2.0, Double(reconnectAttempts - 1))
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.logger.log("Reconnect attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts)", category: "BLE")
            self.centralManager.connect(peripheral, options: nil)
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        isReconnecting = false
        reconnectAttempts = 0
    }
}