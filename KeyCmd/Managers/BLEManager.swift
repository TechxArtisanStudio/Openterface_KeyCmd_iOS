import CoreBluetooth
import Combine
import SwiftUI

final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // MARK: - Connection State

    enum ConnectionState {
        case disconnected, connecting, connected, reconnecting
    }

    // MARK: - Constants (aligned with Android BluetoothService)

    private enum BLEConstants {
        /// Target MTU to negotiate on connect (Android: BLE_ETH_TARGET_MTU)
        static let targetMTU = 247
        /// Maximum chunk size for BLE writes (Android: SAFE_BLE_STREAM_CHUNK)
        static let safeChunkSize = 128
        /// Delay between chunks in milliseconds (Android: BLE_ETH_INTER_CHUNK_DELAY_MS)
        static let interChunkDelayMs = 10
        /// BLE-Eth frame command byte index
        static let frameCmdIndex = 3
        /// BLE-Eth control commands
        static let cmdConnect: UInt8 = 0x10
        static let cmdDisconnect: UInt8 = 0x12
        static let cmdInfo: UInt8 = 0x1F
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastConnectedUUID = "ble_last_connected_uuid"
        static let lastConnectedName = "ble_last_connected_name"
        static let autoConnectEnabled = "ble_auto_connect_enabled"
    }

    // MARK: - Published State

    @Published var discoveredDevices: [(CBPeripheral, NSNumber, String?)] = []  // (peripheral, rssi, advName)
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
    private let bleQueue = DispatchQueue(label: "com.keycmd.ble", qos: .userInitiated)
    private let bleEthWriteQueue = DispatchQueue(label: "com.keycmd.bleEth.write", qos: .userInitiated)
    private let logger = LogManager.shared

    private var connectedPeripheral: CBPeripheral?
    private var fff2Characteristic: CBCharacteristic?
    private var fff1Characteristic: CBCharacteristic?

    // ponytail: simple exponential backoff, capped at 3 retries (Android uses 1 with 5s delay)
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts = 3
    private var reconnectWorkItem: DispatchWorkItem?
    private var rssiTimer: Timer?
    private var pendingConnectionStartedAt: Date?
    private var discoveryTimestamps: [UUID: Date] = [:]  // Track last discovery time per device

    /// Raw data publish/subscribe for BLE-Eth transport (bypasses HID parsing).
    let rawDataSubject = PassthroughSubject<Data, Never>()

    var showPopupBinding: Binding<Bool>?

    // MARK: - Init

    override init() {
        super.init()
        lastConnectedDeviceName = UserDefaults.standard.string(forKey: Keys.lastConnectedName)
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
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
            DispatchQueue.main.async { self.connectionState = .disconnected }
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
            beginConnecting(to: peripheral, isReconnecting: true)
        }
    }

    private func normalizedDeviceName(_ name: String?) -> String {
        guard let name else { return "" }
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = lowered.filter { $0.isLetter || $0.isNumber }
        return filtered
    }

    private func shouldAutoConnect(to peripheral: CBPeripheral, advertisementName: String?) -> Bool {
        guard autoConnectEnabled else { return false }

        if let uuidString = UserDefaults.standard.string(forKey: Keys.lastConnectedUUID),
           let uuid = UUID(uuidString: uuidString),
           peripheral.identifier == uuid {
            return true
        }

        let lastConnectedNameRaw = UserDefaults.standard.string(forKey: Keys.lastConnectedName)
        let lastConnectedName = normalizedDeviceName(lastConnectedNameRaw)

        let discoveredName = normalizedDeviceName(peripheral.name ?? advertisementName)
        guard !discoveredName.isEmpty else { return false }

        // If we don't have a usable saved name (e.g. "Unknown"), fall back to first compatible
        // discovery so startup doesn't remain in endless scan mode.
        if lastConnectedName.isEmpty || lastConnectedName == "unknown" {
            logger.log("No usable saved device name, auto-connecting to compatible discovery", category: "BLE", level: .warning)
            return true
        }

        if discoveredName == lastConnectedName ||
            discoveredName.contains(lastConnectedName) ||
            lastConnectedName.contains(discoveredName) {
            logger.log("Auto-connect matched by name fallback: \(discoveredName)", category: "BLE")
            return true
        }
        return false
    }

    private func beginConnecting(to peripheral: CBPeripheral, isReconnecting: Bool = false) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        pendingConnectionStartedAt = Date()
        DispatchQueue.main.async {
            self.connectionState = .connecting
            self.isReconnecting = isReconnecting
        }
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
        startConnectionTimeout(for: peripheral)
    }

    func checkBluetoothPermission() -> Bool {
        centralManager.state == .poweredOn
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // ponytail: prefer advName over peripheral.name — KVM-Go doesn't populate peripheral.name until connected,
        // and on iOS the cached peripheral.name can be stale/wrong for previously-seen-but-unconnected devices.
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let displayName = advName ?? peripheral.name
        let deviceName = (displayName ?? "").lowercased()

        let isKnownDevice = !deviceName.isEmpty &&
            (deviceName.hasPrefix("openterface") || deviceName.hasPrefix("kvm") || deviceName.hasPrefix("keymod"))
        guard isKnownDevice else { return }

        // Calculate time delta since last discovery
        let now = Date()
        let timeDeltaMs: Double
        if let lastSeen = discoveryTimestamps[peripheral.identifier] {
            timeDeltaMs = now.timeIntervalSince(lastSeen) * 1000
        } else {
            timeDeltaMs = 0
        }
        discoveryTimestamps[peripheral.identifier] = now

        // Calculate distance estimate from RSSI (path loss model)
        // Formula: distance = 10^((txPower - RSSI) / (10 * n))
        // txPower = -59 dBm (typical RSSI at 1m), n = 2.0 (free space)
        let rssiValue = RSSI.doubleValue
        let txPower = -59.0
        let pathLossExponent = 2.0
        let distanceMeters = pow(10.0, (txPower - rssiValue) / (10.0 * pathLossExponent))
        let distanceCm = Int(distanceMeters * 100)
        let distanceStr = distanceCm < 100 ? "\(distanceCm)cm" : String(format: "%.1fm", distanceMeters)

        logger.log("Discovered device: \(displayName ?? "Unknown") \(Int(rssiValue)) dBm(\(String(format: "%.2f", timeDeltaMs))ms) \(distanceStr)", category: "BLE")

        DispatchQueue.main.async {
            if let existingIndex = self.discoveredDevices.firstIndex(where: { $0.0.identifier == peripheral.identifier }) {
                self.discoveredDevices[existingIndex] = (peripheral, RSSI, advName)
            } else {
                self.discoveredDevices.append((peripheral, RSSI, advName))
                self.logger.log("Added \(displayName ?? "Unknown") to discoveredDevices (total: \(self.discoveredDevices.count))", category: "BLE", level: .debug)
            }
        }

        guard shouldAutoConnect(to: peripheral, advertisementName: advName) else {
            logger.log("Device \(displayName ?? "Unknown") does not match auto-connect criteria", category: "BLE", level: .debug)
            return
        }

        if connectionState == .connected {
            logger.log("Already connected, skipping auto-connect", category: "BLE")
            return
        }

        // When connection state is stale (connecting to another peripheral for too long),
        // recover by switching to the discovered auto-connect target.
        if connectionState == .connected || connectionState == .connecting || connectionState == .reconnecting {
            let isSamePeripheral = connectedPeripheral?.identifier == peripheral.identifier
            if isSamePeripheral {
                logger.log("Already connecting to auto-connect target, skipping", category: "BLE")
                return
            }

            if let startedAt = pendingConnectionStartedAt,
               Date().timeIntervalSince(startedAt) < 3.0 {
                logger.log("Connection in progress to another peripheral, waiting...", category: "BLE")
                return
            }

            logger.log("Stale connecting state detected, switching auto-connect target", category: "BLE", level: .warning)
            if let current = connectedPeripheral, current.identifier != peripheral.identifier {
                centralManager.cancelPeripheralConnection(current)
            }
            cancelConnectionTimeout()
        }

        logger.log("Auto-connect target discovered, connecting...", category: "BLE")
        beginConnecting(to: peripheral, isReconnecting: false)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.log("Connected to \(peripheral.name ?? "Unknown") (id=\(peripheral.identifier.uuidString))", category: "BLE", level: .success)
        cancelConnectionTimeout()
        central.stopScan()
        logger.log("Stopped BLE scan after connection", category: "BLE", level: .debug)
        pendingConnectionStartedAt = nil
        connectedPeripheral = peripheral
        reconnectAttempts = 0
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        logger.log("Starting service discovery (FFF0 only)...", category: "BLE")
        peripheral.discoverServices([CBUUID(string: "FFF0")])

        // Note: iOS CoreBluetooth handles MTU negotiation automatically (unlike Android).
        // We use 128-byte chunks in sendRawData() which is safe for any MTU size.

        startRSSIMonitoring()

        // Persist last connected device for auto-reconnect
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Keys.lastConnectedUUID)
        let deviceName = peripheral.name ?? "Unknown"
        UserDefaults.standard.set(deviceName, forKey: Keys.lastConnectedName)
        DispatchQueue.main.async {
            self.connectedDevices.insert(peripheral.identifier)
            self.connectionState = .connected
            self.isReconnecting = false
            self.lastConnectedDeviceName = deviceName
            self.showPopupBinding?.wrappedValue = false
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        cancelConnectionTimeout()
        pendingConnectionStartedAt = nil
        logger.log("Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "Unknown error")", category: "BLE", level: .error)
        DispatchQueue.main.async {
            self.connectionState = .disconnected
            self.isReconnecting = false
        }
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

        logger.log("Discovered \(services.count) services", category: "BLE")
        for service in services {
            logger.log("Service UUID: \(service.uuid)", category: "BLE")
            peripheral.discoverCharacteristics([CBUUID(string: "FFF1"), CBUUID(string: "FFF2")], for: service)
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

        logger.log("Characteristics for service \(service.uuid) (\(characteristics.count) found):", category: "BLE")
        for characteristic in characteristics {
            logger.log("Characteristic UUID: \(characteristic.uuid) properties=\(characteristic.properties.rawValue)", category: "BLE")
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
                    logger.log("FFF1 notifications enabling...", category: "BLE", level: .success)
                } else {
                    logger.log("FFF1 does NOT support notify", category: "BLE", level: .warning)
                }
            }
        }
    }

    func connectToDevice(_ peripheral: CBPeripheral) {
        logger.log("Connecting to \(peripheral.name ?? "Unknown")", category: "BLE")
        cancelReconnect()
        beginConnecting(to: peripheral, isReconnecting: false)
    }

    func disconnectDevice(_ peripheral: CBPeripheral) {
        logger.log("Disconnecting from \(peripheral.name ?? "Unknown") (id=\(peripheral.identifier.uuidString.prefix(8))...)", category: "BLE", level: .info)
        cancelConnectionTimeout()
        pendingConnectionStartedAt = nil
        cancelReconnect()
        // Clear persisted last device (user explicitly disconnected)
        UserDefaults.standard.removeObject(forKey: Keys.lastConnectedUUID)
        UserDefaults.standard.removeObject(forKey: Keys.lastConnectedName)
        DispatchQueue.main.async {
            self.lastConnectedDeviceName = nil
            self.connectionState = .disconnected
            self.logger.log("Connection state set to .disconnected", category: "BLE", level: .debug)
        }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    /// Disconnect currently connected device (convenience for UI)
    func disconnectCurrentDevice() {
        if let peripheral = connectedPeripheral {
            logger.log("Disconnecting current device via UI", category: "BLE", level: .info)
            disconnectDevice(peripheral)
        } else {
            logger.log("No connected device to disconnect", category: "BLE", level: .warning)
        }
    }

    func startScanning() {
        if centralManager.state == .poweredOn {
            logger.log("Starting BLE scan", category: "BLE")
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            logger.log("Cannot start scanning, Bluetooth is not powered on", category: "BLE", level: .warning)
        }
    }

    func stopScanning() {
        logger.log("Stopping BLE scan", category: "BLE", level: .debug)
        centralManager.stopScan()
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
    /// Mirrors Android BluetoothService.writeBleEthData():
    /// - Control frames (CONNECT/DISCONNECT/INFO) use acknowledged writes
    /// - Data frames use unacknowledged writes
    /// - Data is chunked to 128 bytes with 10ms inter-chunk delay
    /// - All writes go through a single-threaded executor queue
    func sendRawData(_ data: Data) {
        guard let connectedPeripheral = connectedPeripheral else {
            logger.log("No connected peripheral", category: "BLE", level: .error)
            return
        }

        guard let fff2Characteristic = fff2Characteristic else {
            logger.log("FFF2 characteristic not found", category: "BLE", level: .error)
            return
        }

        // Determine if this is a control frame (needs acknowledged write)
        // Try .withResponse for all frames — device may need BLE-level ACK before forwarding
        let isControlFrame = isControlFrame(data: data)
        let writeType: CBCharacteristicWriteType = .withResponse

        logger.log("BLE-Eth TX \(data.count) bytes, controlFrame=\(isControlFrame), writeType=\(isControlFrame ? "withResponse" : "withoutResponse")", category: "BLE", level: .debug)

        // Enqueue write operation to single-threaded executor (matches Android)
        bleEthWriteQueue.async { [weak self] in
            guard let self = self else { return }

            // Check if data needs chunking
            if data.count <= BLEConstants.safeChunkSize {
                // Single write
                self.performWrite(
                    peripheral: connectedPeripheral,
                    characteristic: fff2Characteristic,
                    data: data,
                    writeType: writeType
                )
            } else {
                // Chunked write with inter-chunk delay
                var offset = 0
                while offset < data.count {
                    let chunkEnd = min(offset + BLEConstants.safeChunkSize, data.count)
                    let chunk = data[offset..<chunkEnd]
                    self.performWrite(
                        peripheral: connectedPeripheral,
                        characteristic: fff2Characteristic,
                        data: Data(chunk),
                        writeType: .withResponse  // all writes need BLE-level ACK
                    )
                    offset = chunkEnd

                    // Inter-chunk delay (except after last chunk)
                    if offset < data.count {
                        Thread.sleep(forTimeInterval: Double(BLEConstants.interChunkDelayMs) / 1000.0)
                    }
                }
            }
        }
    }

    /// Check if a BLE-Eth frame is a control command (CONNECT/DISCONNECT/INFO)
    private func isControlFrame(data: Data) -> Bool {
        guard data.count > BLEConstants.frameCmdIndex else { return false }
        let cmd = data[BLEConstants.frameCmdIndex]
        return cmd == BLEConstants.cmdConnect
            || cmd == BLEConstants.cmdDisconnect
            || cmd == BLEConstants.cmdInfo
    }

    /// Perform a single BLE write operation
    private func performWrite(
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        data: Data,
        writeType: CBCharacteristicWriteType
    ) {
        // Check if characteristic supports the requested write type
        let supportsWriteType: Bool
        if writeType == .withResponse {
            supportsWriteType = characteristic.properties.contains(.write)
        } else {
            supportsWriteType = characteristic.properties.contains(.writeWithoutResponse)
        }

        if !supportsWriteType {
            logger.log("Characteristic doesn't support \(writeType == .withResponse ? "write" : "writeWithoutResponse")", category: "BLE", level: .error)
            return
        }

        peripheral.writeValue(data, for: characteristic, type: writeType)
        logger.log("BLE-Eth wrote \(data.count) bytes", category: "BLE", level: .debug)
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
            logger.log("FFF1 notification: \(data.count) bytes", category: "BLE")
            // Raw data from BLE-Eth tunnel — publish to subscribers
            rawDataSubject.send(data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.log("Notification state update failed for \(characteristic.uuid): \(error.localizedDescription)", category: "BLE", level: .error)
            return
        }
        logger.log("Notification state for \(characteristic.uuid): \(characteristic.isNotifying ? "enabled" : "disabled")", category: "BLE", level: .success)
    }

    func sendMouseMove(dx: Int, dy: Int) {
        var dx8 = Int8(clamping: dx)
        var dy8 = Int8(clamping: dy)
        let data = Data(bytes: &dx8, count: 1) + Data(bytes: &dy8, count: 1)
        sendTouchData(data: data)
    }

    private func startRSSIMonitoring() {
        guard let peripheral = connectedPeripheral else {
            logger.log("RSSI monitoring: no connected peripheral", category: "BLE", level: .warning)
            return
        }

        logger.log("Starting RSSI monitoring for \(peripheral.name ?? "Unknown")", category: "BLE", level: .info)
        rssiTimer?.invalidate()
        peripheral.readRSSI()

        // ponytail: weak self to prevent retain cycle; stored timer so it can be invalidated
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let peripheral = self.connectedPeripheral else {
                self?.logger.log("RSSI timer skipped: no connected peripheral", category: "BLE", level: .warning)
                return
            }
            self.logger.log("RSSI timer fired, calling readRSSI() for \(peripheral.name ?? "Unknown")", category: "BLE", level: .info)
            peripheral.readRSSI()
        }
        // Ensure timer runs during scroll/tracking modes
        RunLoop.main.add(timer, forMode: .common)
        rssiTimer = timer
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

        logger.log("RSSI updated: \(RSSI.intValue) dBm", category: "BLE", level: .info)
        DispatchQueue.main.async {
            self.currentRSSI = RSSI
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let nsError = error as NSError?
        let domain = nsError?.domain ?? "nil"
        let code = nsError?.code ?? -1
        let desc = error?.localizedDescription ?? "nil"
        logger.log("Disconnected from \(peripheral.name ?? "Unknown") | error domain=\(domain) code=\(code) desc=\(desc)", category: "BLE", level: .warning)
        stopRSSIMonitoring()

        if peripheral.identifier == connectedPeripheral?.identifier {
            connectedPeripheral = nil
            fff2Characteristic = nil
            fff1Characteristic = nil
        }

        // ponytail: auto-reconnect on unexpected disconnect (error != nil means not user-initiated)
        if error != nil && autoConnectEnabled {
            DispatchQueue.main.async {
                self.connectedDevices.remove(peripheral.identifier)
                self.connectionState = .reconnecting
            }
            scheduleReconnect(for: peripheral)
        } else {
            DispatchQueue.main.async {
                self.connectedDevices.remove(peripheral.identifier)
                self.connectionState = .disconnected
            }
        }
    }

    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        logger.log("Connection event: \(event.rawValue) for \(peripheral.name ?? "Unknown")", category: "BLE")
    }

    // MARK: - Reconnect Logic

    private func scheduleReconnect(for peripheral: CBPeripheral) {
        guard reconnectAttempts < maxReconnectAttempts else {
            logger.log("Max reconnect attempts reached, giving up", category: "BLE", level: .warning)
            DispatchQueue.main.async {
                self.connectionState = .disconnected
                self.isReconnecting = false
            }
            // ponytail: reset counter only after giving up so next disconnect cycle
            // starts fresh (but consecutive attempts use proper backoff)
            reconnectAttempts = 0
            return
        }

        // ponytail: cancel any pending reconnect work item but DON'T reset counter
        // — counter must accumulate across attempts for exponential backoff to work
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        reconnectAttempts += 1
        DispatchQueue.main.async { self.isReconnecting = true }

        // ponytail: exponential backoff 1s, 2s, 4s (Android uses fixed 5s)
        let delay = pow(2.0, Double(reconnectAttempts - 1))
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.logger.log("Reconnect attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts)", category: "BLE")
            // ponytail: connect on BLE queue for consistency with centralManager delegate
            self.bleQueue.async {
                self.beginConnecting(to: peripheral, isReconnecting: true)
            }
        }
        reconnectWorkItem = workItem
        // ponytail: schedule delay on main queue, but actual connect runs on BLE queue
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Cancel any pending reconnect and reset the attempt counter.
    /// Called when user explicitly connects/disconnects — fresh start.
    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        DispatchQueue.main.async { self.isReconnecting = false }
        reconnectAttempts = 0
    }

    // MARK: - Connection Timeout

    /// Start a 10-second timeout for a pending connection.
    /// If the connection doesn't complete (didConnect/didFailToConnect) within that window,
    /// reset the state to disconnected so the next scan cycle can try again.
    private var connectionTimeoutWorkItem: DispatchWorkItem?

    private func startConnectionTimeout(for peripheral: CBPeripheral) {
        cancelConnectionTimeout()
        let name = peripheral.name ?? "Unknown"
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.logger.log("Connection timeout for \(name), resetting state", category: "BLE", level: .warning)
            self.pendingConnectionStartedAt = nil
            DispatchQueue.main.async {
                self.connectionState = .disconnected
                self.isReconnecting = false
            }
        }
        connectionTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: workItem)
    }

    private func cancelConnectionTimeout() {
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
    }
}