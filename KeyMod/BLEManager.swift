import CoreBluetooth
import Combine
import SwiftUI // Added import for SwiftUI to use Binding.

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var discoveredDevices: [(CBPeripheral, NSNumber)] = []
    @Published var connectedDevices: Set<UUID> = []
    private var centralManager: CBCentralManager!
    
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
            print("Bluetooth is powered on")
        case .poweredOff:
            print("Bluetooth is powered off")
        case .unsupported:
            print("Bluetooth is unsupported")
        case .unauthorized:
            print("Bluetooth permission not granted")
        default:
            print("Bluetooth state is unknown")
        }
    }

    func checkBluetoothPermission() -> Bool {
        return centralManager.state == .poweredOn
    }

    // Ensure the peripheral delegate is set when connecting.
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let name = peripheral.name?.lowercased(), name.hasPrefix("openterface") {
            print("Discovered device: \(peripheral.name ?? "Unknown")")
            print("RSSI: \(RSSI)")
            if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                print("Service UUIDs from advertisement: \(serviceUUIDs)")
            }
            peripheral.delegate = self // Set the delegate to ensure callbacks are triggered
            centralManager.connect(peripheral, options: nil)
            discoveredDevices.append((peripheral, RSSI))
        }
    }

    // Updated didConnect method to auto-hide the popup panel after a BLE device is connected.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown")")
        connectedPeripheral = peripheral // Store the connected peripheral
        connectedDevices.insert(peripheral.identifier)
        peripheral.discoverServices(nil)

        DispatchQueue.main.async {
            self.showPopupBinding?.wrappedValue = false
        }
    }

    // Added logic to list all characteristics of the BLE device after connected.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            print("No services found")
            return
        }

        for service in services {
            print("Service UUID: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    // Update didDiscoverCharacteristics to find and store FFF2 characteristic
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            print("No characteristics found for service \(service.uuid)")
            return
        }

        print("Characteristics for service \(service.uuid):")
        for characteristic in characteristics {
            print("Characteristic UUID: \(characteristic.uuid)")
            // Store FFF2 characteristic when found
            if characteristic.uuid == CBUUID(string: "FFF2") {
                fff2Characteristic = characteristic
                print("FFF2 characteristic found!")
            }
        }
    }

    func connectToDevice(_ peripheral: CBPeripheral) {
        print("Connecting to \(peripheral.name ?? "Unknown")")
        centralManager.connect(peripheral, options: nil)
    }

    func disconnectDevice(_ peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func startScanning() {
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            print("Cannot start scanning, Bluetooth is not powered on")
        }
    }

    // Added a method to send binary data to a BLE service.
    func sendData(to peripheral: CBPeripheral, data: Data, characteristic: CBCharacteristic) {
        guard characteristic.properties.contains(.write) else {
            print("Characteristic does not support writing.")
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        print("Data sent: \(data)")
    }

    // Fix the sendTouchData method
    func sendTouchData(data: Data) {
        guard let connectedPeripheral = connectedPeripheral else {
            print("No connected peripheral.")
            return
        }

        guard let fff2Characteristic = fff2Characteristic else {
            print("FFF2 characteristic not found.")
            return
        }

        guard fff2Characteristic.properties.contains(.write) else {
            print("FFF2 characteristic does not support writing.")
            return
        }

        connectedPeripheral.writeValue(data, for: fff2Characteristic, type: .withoutResponse)
        print("Data sent to FFF2 characteristic: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }
}
