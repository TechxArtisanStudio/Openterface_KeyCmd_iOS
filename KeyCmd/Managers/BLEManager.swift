import CoreBluetooth
import Combine
import SwiftUI

final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var discoveredDevices: [(CBPeripheral, NSNumber)] = []
    @Published var connectedDevices: Set<UUID> = []
    @Published var currentRSSI: NSNumber? = nil
    @Published var isConnecting: Bool = false

    private var centralManager: CBCentralManager!
    private let logger = LogManager.shared

    private var connectedPeripheral: CBPeripheral?
    private var fff2Characteristic: CBCharacteristic?
    private var fff1Characteristic: CBCharacteristic?

    /// Raw data publish/subscribe for BLE-Eth transport (bypasses HID parsing).
    let rawDataSubject = PassthroughSubject<Data, Never>()

    var showPopupBinding: Binding<Bool>?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.log("Bluetooth is powered on", category: "BLE", level: .success)
        case .poweredOff:
            logger.log("Bluetooth is powered off", category: "BLE", level: .warning)
        case .unsupported:
            logger.log("Bluetooth is unsupported", category: "BLE", level: .error)
        case .unauthorized:
            logger.log("Bluetooth permission not granted", category: "BLE", level: .error)
        default:
            logger.log("Bluetooth state is unknown", category: "BLE", level: .warning)
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
            isConnecting = true
            centralManager.connect(peripheral, options: nil)
            discoveredDevices.append((peripheral, RSSI))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.log("Connected to \(peripheral.name ?? "Unknown")", category: "BLE", level: .success)
        connectedPeripheral = peripheral
        connectedDevices.insert(peripheral.identifier)
        isConnecting = false
        peripheral.discoverServices(nil)
        startRSSIMonitoring()

        DispatchQueue.main.async {
            self.showPopupBinding?.wrappedValue = false
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.log("Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "Unknown error")", category: "BLE", level: .error)
        isConnecting = false
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
        centralManager.connect(peripheral, options: nil)
    }

    func disconnectDevice(_ peripheral: CBPeripheral) {
        logger.log("Disconnecting from device", category: "BLE")
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

        peripheral.readRSSI()

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if self.connectedPeripheral != nil && self.connectedDevices.contains(peripheral.identifier) {
                peripheral.readRSSI()
            }
        }
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

        if peripheral.identifier == connectedPeripheral?.identifier {
            connectedPeripheral = nil
            fff2Characteristic = nil
            fff1Characteristic = nil
            currentRSSI = nil
        }
    }
}