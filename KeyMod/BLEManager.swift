import CoreBluetooth
import Combine
import SwiftUI // Added import for SwiftUI to use Binding.

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var discoveredDevices: [(CBPeripheral, NSNumber)] = []
    @Published var connectedDevices: Set<UUID> = []
    @Published var currentRSSI: NSNumber? = nil
    private var centralManager: CBCentralManager!
    private let logger = LogManager.shared
    
    // Add these properties
    private var connectedPeripheral: CBPeripheral?
    private var fff2Characteristic: CBCharacteristic?
    
    // Added a reference to the ContentView's showPopup state.
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
        return centralManager.state == .poweredOn
    }

    // Ensure the peripheral delegate is set when connecting.
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let name = peripheral.name?.lowercased(), (name.hasPrefix("openterface") || name.hasPrefix("kvm")) {
            logger.log("Discovered device: \(peripheral.name ?? "Unknown")", category: "BLE")
            logger.log("RSSI\(RSSI)", category: "BLE")
            if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                logger.log("Service UUIDs from advertisement: \(serviceUUIDs)", category: "BLE")
            }
            peripheral.delegate = self // Set the delegate to ensure callbacks are triggered
            centralManager.connect(peripheral, options: nil)
            discoveredDevices.append((peripheral, RSSI))
        }
    }

    // Updated didConnect method to auto-hide the popup panel after a BLE device is connected.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.log("Connected to \(peripheral.name ?? "Unknown")", category: "BLE", level: .success)
        connectedPeripheral = peripheral // Store the connected peripheral
        connectedDevices.insert(peripheral.identifier)
        peripheral.discoverServices(nil)

        // Start RSSI monitoring
        startRSSIMonitoring()

        DispatchQueue.main.async {
            self.showPopupBinding?.wrappedValue = false
        }
    }

    // Added logic to list all characteristics of the BLE device after connected.
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

    // Update didDiscoverCharacteristics to find and store FFF2 characteristic
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
            // Store FFF2 characteristic when found
            if characteristic.uuid == CBUUID(string: "FFF2") {
                fff2Characteristic = characteristic
                logger.log("FFF2 characteristic found!", category: "BLE", level: .success)
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

    // Added a method to send binary data to a BLE service.
    func sendData(to peripheral: CBPeripheral, data: Data, characteristic: CBCharacteristic) {
        guard characteristic.properties.contains(.write) else {
            logger.log("Characteristic does not support writing", category: "BLE", level: .error)
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.logHex(hexString, message: "Data sent", category: "BLE")
    }

    // Fix the sendTouchData method
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

    // Send mouse move values over BLE
    func sendMouseMove(dx: Int, dy: Int) {
        // Example: Pack dx and dy as two Int8 values into Data
        var dx8 = Int8(clamping: dx)
        var dy8 = Int8(clamping: dy)
        let data = Data(bytes: &dx8, count: 1) + Data(bytes: &dy8, count: 1)
        sendTouchData(data: data)
    }

    // RSSI monitoring methods
    private func startRSSIMonitoring() {
        guard let peripheral = connectedPeripheral else { return }
        
        // Read RSSI immediately
        peripheral.readRSSI()
        
        // Set up timer to read RSSI periodically (every 2 seconds)
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if self.connectedPeripheral != nil && self.connectedDevices.contains(peripheral.identifier) {
                peripheral.readRSSI()
            }
        }
    }
    
    // Handle RSSI reading result
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error = error {
            logger.log("Error reading RSSI: \(error.localizedDescription)", category: "BLE", level: .error)
            return
        }
        
        DispatchQueue.main.async {
            self.currentRSSI = RSSI
//            self.logger.log("Current RSSI: \(RSSI) dBm", category: "BLE")
        }
    }
    
    // Clean up RSSI when disconnected
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.log("Disconnected from \(peripheral.name ?? "Unknown")", category: "BLE", level: .warning)
        connectedDevices.remove(peripheral.identifier)
        
        if peripheral.identifier == connectedPeripheral?.identifier {
            connectedPeripheral = nil
            fff2Characteristic = nil
            currentRSSI = nil
        }
    }
}
