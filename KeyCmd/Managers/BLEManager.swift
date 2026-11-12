// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import CoreBluetooth
import Combine
import SwiftUI

final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // MARK: - Connection State

    enum ConnectionState {
        case disconnected, connecting, connected, reconnecting
    }

    enum RenameFailure: Equatable {
        case notConnected
        case noResponse
        case rejected(UInt8)
        case disconnected
        case reconnectTimeout
    }

    enum RenameState: Equatable {
        case idle
        case sending
        case waitingForReboot
        case success
        case failure(RenameFailure)
    }

    enum ECMIPFailure: Equatable {
        case notConnected
        case busy
        case noResponse
        case rejected(UInt8)
        case invalidResponse
        case disconnected
    }

    enum ECMIPState: Equatable {
        case idle
        case fetching
        case fetched(ECMIPCommand.Config)
        case saving
        case failure(ECMIPFailure)
    }

    enum PairingIssue: Equatable {
        case authenticationFailed
        case staleBond
        case timeout
        case connectionFailed
    }

    enum SecurityFailure: Equatable {
        case notConnected
        case busy
        case noResponse
        case rejected(UInt8)
        case invalidResponse
        case disconnected
    }

    enum SecurityState: Equatable {
        case idle
        case loading
        case ready(BLESecurityCommand.Status)
        case savingPIN
        case pinSaved
        case erasing
        case erased
        case unsupportedFirmware
        case failure(SecurityFailure)
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
        static let knownDeviceUUIDs = "ble_known_device_uuids"
        static let pairedDeviceUUIDs = "ble_paired_device_uuids"
        static let pinChangedUUIDs = "ble_pin_changed_device_uuids"
    }

    // MARK: - Published State

    @Published var discoveredDevices: [(CBPeripheral, NSNumber, String?)] = []  // (peripheral, rssi, advName)
    @Published var connectedDevices: Set<UUID> = []
    @Published var currentRSSI: NSNumber? = nil
    @Published var connectionState: ConnectionState = .disconnected
    @Published var isReconnecting: Bool = false
    @Published var lastConnectedDeviceName: String?
    /// Flipped on when user tries to send HID without a BLE connection; drives a one-time warning alert.
    @Published var showNoConnectionWarning: Bool = false
    @Published private(set) var renameState: RenameState = .idle
    @Published private(set) var ecmIPState: ECMIPState = .idle
    /// Last config read back from the device; the terminal uses its target IP
    /// as the default SSH host.
    @Published private(set) var lastECMIPConfig: ECMIPCommand.Config?
    /// True between opening the GATT connection and a successful FFF1 subscription.
    /// The link is only encrypted (and usable) once notifications are enabled.
    @Published private(set) var isWaitingForPairing: Bool = false
    @Published private(set) var pairingIssue: PairingIssue?
    @Published private(set) var securityState: SecurityState = .idle
    /// One-time hint after the first successful connection by this app. The
    /// firmware cannot report whether the factory PIN is still in effect.
    @Published private(set) var showFactoryPINReminder: Bool = false
    /// PIN this app last set for the connected device, loaded from Keychain.
    /// The device never reports its current PIN, so this may be stale.
    @Published private(set) var cachedPairingPIN: String?

    // ponytail: mirrors Android's auto-connect checkbox
    var autoConnectEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoConnectEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoConnectEnabled) }
    }

    /// One-time "factory PIN" hint toggle (Settings > General). Defaults to on
    /// when the key has never been written.
    static let factoryPINReminderKey = "ble_factory_pin_reminder_enabled"

    static var factoryPINReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: factoryPINReminderKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: factoryPINReminderKey) }
    }

    // MARK: - Private State

    private var centralManager: CBCentralManager!
    private let bleQueue = DispatchQueue(label: "com.keycmd.ble", qos: .userInitiated)
    private let bleEthWriteQueue = DispatchQueue(label: "com.keycmd.bleEth.write", qos: .userInitiated)
    /// Serializes every HID report and owns the relative-move coalescing state.
    private let hidWriteQueue = DispatchQueue(label: "com.keycmd.hid.write", qos: .userInteractive)
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

    // Rename flow state — accessed on bleQueue only, except @Published renameState (main).
    private var renameScanner: BLENameCommand.ResponseScanner?
    private var pendingRenameName: String?
    private var renameRebootIdentifier: UUID?
    private var renameResponseTimeout: DispatchWorkItem?
    private var renameRebootTimeout: DispatchWorkItem?

    // ECM IP flow state — accessed on bleQueue only, except @Published ecmIPState (main).
    // Mutually exclusive with the rename window: both scanners claim cmd 0xA3.
    private var ecmScanner: BLENameCommand.ResponseScanner?
    private var ecmResponseTimeout: DispatchWorkItem?

    // Pairing / security flow state — accessed on bleQueue only.
    // The security window claims 0xA2, which ECM SET also uses, so all three
    // control windows must stay mutually exclusive.
    private enum SecurityRequest {
        case status
        case setPIN
        case erase
    }

    private var awaitingPairing = false
    private var pairingTimeout: DispatchWorkItem?
    private var pairingNotifyRetries = 0
    private var suppressAutoReconnect = false
    private var securityScanner: BLENameCommand.ResponseScanner?
    private var securityResponseTimeout: DispatchWorkItem?
    private var pendingSecurityRequest: SecurityRequest?
    private var pendingPINIsFactory = false
    private var pendingPINToCache: String?
    private var awaitingResetDisconnect = false

    // Relative-move coalescing state — mutated only on hidWriteQueue.
    private var pendingMoveDx = 0
    private var pendingMoveDy = 0
    private var pendingMoveButtons: UInt8 = 0
    private var pendingMovePeripheral: CBPeripheral?
    private var pendingMoveCharacteristic: CBCharacteristic?

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

        if Self.knownDeviceUUIDs.contains(peripheral.identifier.uuidString) {
            logger.log("Auto-connect matched a known device UUID", category: "BLE")
            return true
        }

        let lastConnectedNameRaw = UserDefaults.standard.string(forKey: Keys.lastConnectedName)
        let lastConnectedName = normalizedDeviceName(lastConnectedNameRaw)

        let discoveredName = normalizedDeviceName(advertisementName ?? peripheral.name)
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

    // MARK: - Known Devices

    /// UUIDs of every device this app has connected to. A renamed device may lose
    /// its known name prefix, and a manual disconnect clears lastConnectedUUID —
    /// this list keeps such devices discoverable afterwards.
    static var knownDeviceUUIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Keys.knownDeviceUUIDs) ?? [])
    }

    static func rememberDeviceUUID(_ identifier: UUID) {
        var known = knownDeviceUUIDs
        guard !known.contains(identifier.uuidString) else { return }
        known.insert(identifier.uuidString)
        UserDefaults.standard.set(Array(known), forKey: Keys.knownDeviceUUIDs)
    }

    /// Primary service, advertised before the runtime name. Unlike the name it
    /// survives renames, so it identifies our devices whatever they are called.
    static let serviceUUID = CBUUID(string: "FFF0")

    static func isDiscoverableDevice(
        name: String?,
        identifier: UUID,
        advertisedServices: [CBUUID] = []
    ) -> Bool {
        if advertisedServices.contains(serviceUUID) { return true }
        // Older firmware may omit the service UUID from the advertisement.
        let deviceName = (name ?? "").lowercased()
        let hasKnownPrefix = !deviceName.isEmpty &&
            (deviceName.hasPrefix("openterface") || deviceName.hasPrefix("kvm") || deviceName.hasPrefix("keymod"))
        if hasKnownPrefix { return true }
        let uuidString = identifier.uuidString
        return uuidString == UserDefaults.standard.string(forKey: Keys.lastConnectedUUID)
            || knownDeviceUUIDs.contains(uuidString)
    }

    private func beginConnecting(to peripheral: CBPeripheral, isReconnecting: Bool = false) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        pendingConnectionStartedAt = Date()
        awaitingPairing = false
        cancelPairingTimeout()
        pairingNotifyRetries = 0
        suppressAutoReconnect = false
        awaitingResetDisconnect = false
        discardPendingMoves()
        DispatchQueue.main.async {
            self.connectionState = .connecting
            self.isReconnecting = isReconnecting
            self.isWaitingForPairing = false
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
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []

        guard Self.isDiscoverableDevice(
            name: displayName,
            identifier: peripheral.identifier,
            advertisedServices: advertisedServices
        ) else { return }

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

        // After a rename the firmware reboots; reconnect by UUID regardless of name or auto-connect setting.
        if let renameID = renameRebootIdentifier, peripheral.identifier == renameID {
            logger.log("Rename target back online, reconnecting...", category: "BLE")
            beginConnecting(to: peripheral, isReconnecting: true)
            return
        }

        guard !suppressAutoReconnect else {
            logger.log("Auto-connect suppressed after pairing failure", category: "BLE", level: .debug)
            return
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
        peripheral.discoverServices([Self.serviceUUID])

        // Note: iOS CoreBluetooth handles MTU negotiation automatically (unlike Android).
        // We use 128-byte chunks in sendRawData() which is safe for any MTU size.

        startRSSIMonitoring()

        // The GATT link is not usable yet: FFF1 and FFF2 require an encrypted
        // link, and iOS only starts pairing when a protected attribute is
        // accessed. finalizeConnection() runs after the FFF1 subscription
        // succeeds. A 120s window covers a slow PIN entry.
        awaitingPairing = true
        startPairingTimeout()
        DispatchQueue.main.async { self.pairingIssue = nil }
    }

    /// Runs on bleQueue. The FFF1 subscription succeeded, so the link is
    /// encrypted and the device will accept FFF2 writes.
    private func finalizeConnection(_ peripheral: CBPeripheral) {
        guard connectedPeripheral?.identifier == peripheral.identifier else { return }
        awaitingPairing = false
        cancelPairingTimeout()
        pairingNotifyRetries = 0

        // Persist last connected device for auto-reconnect only after the
        // encrypted link is proven. A failed pairing must not leave a stale
        // auto-connect target behind.
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Keys.lastConnectedUUID)
        Self.rememberDeviceUUID(peripheral.identifier)

        let deviceName: String
        if renameRebootIdentifier == peripheral.identifier {
            // iOS can report a stale cached peripheral.name right after the rename reboot.
            deviceName = pendingRenameName ?? peripheral.name ?? "Unknown"
            finishRename(.success)
        } else {
            deviceName = peripheral.name ?? "Unknown"
        }
        UserDefaults.standard.set(deviceName, forKey: Keys.lastConnectedName)

        let firstConnection = markDeviceSeen(peripheral.identifier)
        let shouldRemindPIN = firstConnection
            && !hasChangedPIN(peripheral.identifier)
            && Self.factoryPINReminderEnabled
        let cachedPIN = PairingPINStore.load(for: peripheral.identifier)

        DispatchQueue.main.async {
            self.connectedDevices.insert(peripheral.identifier)
            self.connectionState = .connected
            self.isReconnecting = false
            self.isWaitingForPairing = false
            self.pairingIssue = nil
            self.lastConnectedDeviceName = deviceName
            self.cachedPairingPIN = cachedPIN
            self.showPopupBinding?.wrappedValue = false
            if shouldRemindPIN { self.showFactoryPINReminder = true }
        }
    }

    private func startPairingTimeout() {
        cancelPairingTimeout()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.awaitingPairing else { return }
            self.logger.log("Pairing timed out waiting for an encrypted link", category: "BLE", level: .warning)
            self.handlePairingFailure(issue: .timeout)
        }
        pairingTimeout = workItem
        bleQueue.asyncAfter(deadline: .now() + 120, execute: workItem)
    }

    private func cancelPairingTimeout() {
        pairingTimeout?.cancel()
        pairingTimeout = nil
    }

    /// Runs on bleQueue. Drops the half-open connection and surfaces a
    /// user-actionable issue; auto-reconnect stays suppressed until the user
    /// manually connects again.
    private func handlePairingFailure(issue: PairingIssue) {
        guard awaitingPairing else { return }
        awaitingPairing = false
        cancelPairingTimeout()
        suppressAutoReconnect = true
        if issue == .staleBond, let identifier = connectedPeripheral?.identifier {
            // The device removed its bond. The only erase path on this
            // firmware (0x22 0x02) also restores the factory PIN, so drop the
            // local "PIN changed" hint and let the factory reminder reappear.
            clearPairingHistory(identifier)
        }
        logger.log("Pairing failed: \(issue)", category: "BLE", level: .error)

        DispatchQueue.main.async {
            self.isWaitingForPairing = false
            self.pairingIssue = issue
            self.connectionState = .disconnected
            self.isReconnecting = false
            if let id = self.connectedPeripheral?.identifier {
                self.connectedDevices.remove(id)
            }
        }
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    private func mapPairingError(_ error: Error) -> PairingIssue {
        if isPeerRemovedPairingInformation(error) { return .staleBond }
        let nsError = error as NSError
        if nsError.domain == CBErrorDomain,
           nsError.code == CBError.encryptionTimedOut.rawValue {
            return .timeout
        }
        return .authenticationFailed
    }

    private func isPeerRemovedPairingInformation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == CBErrorDomain
            && nsError.code == CBError.peerRemovedPairingInformation.rawValue
    }

    private func isPairingRelatedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == CBErrorDomain {
            return nsError.code == CBError.peerRemovedPairingInformation.rawValue
                || nsError.code == CBError.encryptionTimedOut.rawValue
        }
        if nsError.domain == CBATTErrorDomain {
            return nsError.code == CBATTError.insufficientEncryption.rawValue
        }
        return false
    }

    private func isInsufficientEncryption(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == CBATTErrorDomain
            && nsError.code == CBATTError.insufficientEncryption.rawValue
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        cancelConnectionTimeout()
        awaitingPairing = false
        cancelPairingTimeout()
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
            if awaitingPairing { handlePairingFailure(issue: .connectionFailed) }
            return
        }

        guard let services = peripheral.services else {
            logger.log("No services found", category: "BLE", level: .warning)
            if awaitingPairing { handlePairingFailure(issue: .connectionFailed) }
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
                let isFirstDiscovery = fff1Characteristic == nil
                fff1Characteristic = characteristic
                logger.log("FFF1 characteristic found!", category: "BLE", level: .success)
                guard isFirstDiscovery else { continue }
                // Enabling notifications writes a protected CCCD on firmware
                // >= 2026-11: iOS takes over and shows the pairing PIN prompt.
                // Success is the only reliable "link encrypted" signal.
                if characteristic.properties.contains(.notify) {
                    DispatchQueue.main.async { self.isWaitingForPairing = true }
                    peripheral.setNotifyValue(true, for: characteristic)
                    logger.log("FFF1 notifications enabling (pairing gate)...", category: "BLE", level: .success)
                } else {
                    logger.log("FFF1 does NOT support notify", category: "BLE", level: .warning)
                    if awaitingPairing { handlePairingFailure(issue: .connectionFailed) }
                }
            }
        }

        if fff1Characteristic == nil, awaitingPairing {
            handlePairingFailure(issue: .connectionFailed)
        }
    }

    func connectToDevice(_ peripheral: CBPeripheral) {
        logger.log("Connecting to \(peripheral.name ?? "Unknown")", category: "BLE")
        cancelReconnect()
        DispatchQueue.main.async {
            self.pairingIssue = nil
            self.securityState = .idle
            self.showFactoryPINReminder = false
        }
        beginConnecting(to: peripheral, isReconnecting: false)
    }

    func disconnectDevice(_ peripheral: CBPeripheral) {
        logger.log("Disconnecting from \(peripheral.name ?? "Unknown") (id=\(peripheral.identifier.uuidString.prefix(8))...)", category: "BLE", level: .info)
        // User-initiated disconnect cancels an in-flight rename before the delegate
        // callback can mistake it for the expected rename reboot.
        bleQueue.async { [self] in
            if pendingRenameName != nil { finishRename(.failure(.disconnected)) }
            if ecmScanner != nil { finishECM(.failure(.disconnected)) }
            if securityScanner != nil { finishSecurity(.failure(.disconnected)) }
            awaitingPairing = false
            cancelPairingTimeout()
            awaitingResetDisconnect = false
        }
        DispatchQueue.main.async { self.isWaitingForPairing = false }
        discardPendingMoves()
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

    // MARK: - Device Rename

    func renameDevice(to newName: String) {
        guard let bytes = BLENameCommand.validatedNameBytes(newName),
              let trimmed = String(bytes: bytes, encoding: .utf8) else { return }
        beginRename(frame: BLENameCommand.frame(cmd: BLENameCommand.cmdSetName, payload: bytes), newName: trimmed)
    }

    func resetDeviceName() {
        beginRename(frame: BLENameCommand.resetNameFrame(), newName: "KVM-GO")
    }

    func dismissRenameResult() {
        switch renameState {
        case .success, .failure:
            renameState = .idle
        default:
            break
        }
    }

    private func beginRename(frame: Data, newName: String) {
        bleQueue.async { [self] in
            guard connectionState == .connected, fff2Characteristic != nil else {
                DispatchQueue.main.async { self.renameState = .failure(.notConnected) }
                return
            }
            guard pendingRenameName == nil, renameRebootIdentifier == nil,
                  ecmScanner == nil, securityScanner == nil else { return }
            pendingRenameName = newName
            renameScanner = BLENameCommand.ResponseScanner()
            DispatchQueue.main.async { self.renameState = .sending }
            sendRawData(frame)

            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.pendingRenameName != nil else { return }
                self.logger.log("Rename response timed out", category: "BLE", level: .warning)
                self.finishRename(.failure(.noResponse))
            }
            renameResponseTimeout = timeout
            bleQueue.asyncAfter(deadline: .now() + 5, execute: timeout)
        }
    }

    /// Runs on bleQueue. Success means the firmware will reboot in 500ms;
    /// keep the pending name until didConnect finalizes with the fresh identity.
    private func handleRenameResponse(_ response: BLENameCommand.Response) {
        renameResponseTimeout?.cancel()
        renameResponseTimeout = nil
        guard let newName = pendingRenameName, renameRebootIdentifier == nil else { return }

        guard response.isSuccess else {
            logger.log("Rename rejected, status=0x\(String(format: "%02X", response.status))", category: "BLE", level: .error)
            finishRename(.failure(.rejected(response.status)))
            return
        }

        logger.log("Rename accepted, waiting for device reboot", category: "BLE", level: .success)
        UserDefaults.standard.set(newName, forKey: Keys.lastConnectedName)
        renameRebootIdentifier = connectedPeripheral?.identifier
        DispatchQueue.main.async {
            self.lastConnectedDeviceName = newName
            self.renameState = .waitingForReboot
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.renameRebootIdentifier != nil else { return }
            self.logger.log("Rename reconnect timed out", category: "BLE", level: .warning)
            self.finishRename(.failure(.reconnectTimeout))
        }
        renameRebootTimeout = timeout
        bleQueue.asyncAfter(deadline: .now() + 20, execute: timeout)
    }

    /// Runs on bleQueue.
    private func finishRename(_ state: RenameState) {
        renameResponseTimeout?.cancel()
        renameResponseTimeout = nil
        renameRebootTimeout?.cancel()
        renameRebootTimeout = nil
        pendingRenameName = nil
        renameRebootIdentifier = nil
        if var scanner = renameScanner {
            let remainder = scanner.flush()
            if !remainder.isEmpty { rawDataSubject.send(remainder) }
        }
        renameScanner = nil
        DispatchQueue.main.async { self.renameState = state }
    }

    // MARK: - ECM IP Config

    func fetchECMIP() {
        beginECMRequest(frame: ECMIPCommand.getFrame(), busyState: .fetching)
    }

    func saveECMIP(_ config: ECMIPCommand.Config) {
        guard let frame = ECMIPCommand.setAllFrame(config) else { return }
        beginECMRequest(frame: frame, busyState: .saving)
    }

    func resetECMIP() {
        beginECMRequest(frame: ECMIPCommand.resetFrame(), busyState: .saving)
    }

    func dismissECMIPResult() {
        if case .failure = ecmIPState { ecmIPState = .idle }
    }

    private func beginECMRequest(frame: Data, busyState: ECMIPState) {
        bleQueue.async { [self] in
            guard connectionState == .connected, fff2Characteristic != nil else {
                DispatchQueue.main.async { self.ecmIPState = .failure(.notConnected) }
                return
            }
            guard ecmScanner == nil else { return }
            guard renameScanner == nil, pendingRenameName == nil,
                  renameRebootIdentifier == nil, securityScanner == nil else {
                DispatchQueue.main.async { self.ecmIPState = .failure(.busy) }
                return
            }
            ecmScanner = BLENameCommand.ResponseScanner(targetCommands: ECMIPCommand.responseCommands)
            DispatchQueue.main.async { self.ecmIPState = busyState }
            sendRawData(frame)
            scheduleECMTimeout()
        }
    }

    /// Runs on bleQueue. A successful SET is followed by a GET readback so the
    /// UI always shows the values the device actually persisted.
    private func handleECMResponse(_ response: BLENameCommand.Response) {
        ecmResponseTimeout?.cancel()
        ecmResponseTimeout = nil
        guard ecmScanner != nil else { return }

        guard response.status == 0x00 else {
            logger.log("ECM IP request rejected, status=0x\(String(format: "%02X", response.status))", category: "BLE", level: .error)
            finishECM(.failure(.rejected(response.status)))
            return
        }

        if response.cmd == 0xA2 {
            logger.log("ECM IP set accepted, reading back config", category: "BLE", level: .success)
            sendRawData(ECMIPCommand.getFrame())
            scheduleECMTimeout()
            return
        }

        guard let config = ECMIPCommand.parseConfig(response.payload) else {
            logger.log("ECM IP GET reply malformed (\(response.payload.count) data bytes)", category: "BLE", level: .error)
            finishECM(.failure(.invalidResponse))
            return
        }
        finishECM(.fetched(config))
    }

    private func scheduleECMTimeout() {
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.ecmScanner != nil else { return }
            self.logger.log("ECM IP response timed out", category: "BLE", level: .warning)
            self.finishECM(.failure(.noResponse))
        }
        ecmResponseTimeout = timeout
        bleQueue.asyncAfter(deadline: .now() + 5, execute: timeout)
    }

    /// Runs on bleQueue.
    private func finishECM(_ state: ECMIPState) {
        ecmResponseTimeout?.cancel()
        ecmResponseTimeout = nil
        if var scanner = ecmScanner {
            let remainder = scanner.flush()
            if !remainder.isEmpty { rawDataSubject.send(remainder) }
        }
        ecmScanner = nil
        DispatchQueue.main.async {
            if case .fetched(let config) = state { self.lastECMIPConfig = config }
            self.ecmIPState = state
        }
    }

    // MARK: - Pairing & Security

    func dismissPairingIssue() {
        pairingIssue = nil
    }

    func dismissFactoryPINReminder() {
        showFactoryPINReminder = false
    }

    func fetchSecurityStatus() {
        beginSecurityRequest(
            frame: BLESecurityCommand.statusFrame(),
            busyState: .loading,
            request: .status
        )
    }

    func setPairingPIN(_ pin: String) {
        guard let frame = BLESecurityCommand.setPINFrame(pin) else { return }
        // Only a factory/non-factory boolean leaves this frame; the PIN itself
        // stays on the BLE queue until the device acknowledges it.
        beginSecurityRequest(
            frame: frame,
            busyState: .savingPIN,
            request: .setPIN,
            isFactoryPIN: pin == "666666",
            pinToCache: pin
        )
    }

    func erasePairing() {
        beginSecurityRequest(
            frame: BLESecurityCommand.eraseBondsFrame(),
            busyState: .erasing,
            request: .erase
        )
    }

    /// Forgets the device on the app side only: disconnects, stops scanning,
    /// and clears auto-connect/pairing records. The iOS system bond cannot be
    /// removed by the app, so the UI must also direct the user to
    /// Settings > Bluetooth > "Forget This Device".
    func forgetPairing() {
        logger.log("Forgetting local pairing state", category: "BLE", level: .warning)
        bleQueue.async { [self] in
            suppressAutoReconnect = true
            awaitingPairing = false
            cancelPairingTimeout()
            pairingNotifyRetries = 0
            awaitingResetDisconnect = false

            if pendingRenameName != nil { finishRename(.failure(.disconnected)) }
            if ecmScanner != nil { finishECM(.failure(.disconnected)) }
            if securityScanner != nil { finishSecurity(.failure(.disconnected)) }

            let identifier = connectedPeripheral?.identifier
            Self.clearLocalPairingState()
            cancelReconnect()
            stopScanning()

            if let peripheral = connectedPeripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }

            DispatchQueue.main.async {
                self.lastConnectedDeviceName = nil
                self.currentRSSI = nil
                self.isWaitingForPairing = false
                self.isReconnecting = false
                self.pairingIssue = nil
                self.showFactoryPINReminder = false
                self.cachedPairingPIN = nil
                self.securityState = .idle
                self.connectionState = .disconnected
                if let identifier { self.connectedDevices.remove(identifier) }
            }
        }
    }

    func dismissSecurityResult() {
        switch securityState {
        case .failure, .pinSaved, .unsupportedFirmware, .erased:
            securityState = .idle
        default:
            break
        }
    }

    private func beginSecurityRequest(
        frame: Data,
        busyState: SecurityState,
        request: SecurityRequest,
        isFactoryPIN: Bool = false,
        pinToCache: String? = nil
    ) {
        bleQueue.async { [self] in
            guard connectionState == .connected, fff2Characteristic != nil else {
                DispatchQueue.main.async { self.securityState = .failure(.notConnected) }
                return
            }
            guard securityScanner == nil else { return }
            guard renameScanner == nil, pendingRenameName == nil,
                  renameRebootIdentifier == nil, ecmScanner == nil else {
                DispatchQueue.main.async { self.securityState = .failure(.busy) }
                return
            }
            pendingSecurityRequest = request
            pendingPINIsFactory = isFactoryPIN
            pendingPINToCache = pinToCache
            securityScanner = BLENameCommand.ResponseScanner(targetCommands: BLESecurityCommand.responseCommands)
            DispatchQueue.main.async { self.securityState = busyState }
            // sendRawData never hex-logs frames; the PIN stays out of logs.
            sendRawData(frame)
            scheduleSecurityTimeout()
        }
    }

    /// Runs on bleQueue.
    private func handleSecurityResponse(_ response: BLENameCommand.Response) {
        securityResponseTimeout?.cancel()
        securityResponseTimeout = nil
        guard securityScanner != nil, let request = pendingSecurityRequest else { return }

        guard response.cmd == 0xA2, response.status == 0x00 else {
            logger.log("Security request rejected, status=0x\(String(format: "%02X", response.status))", category: "BLE", level: .error)
            finishSecurity(.failure(.rejected(response.status)))
            return
        }

        switch request {
        case .status:
            guard let status = BLESecurityCommand.parseStatus(response.payload) else {
                finishSecurity(.failure(.invalidResponse))
                return
            }
            finishSecurity(status.isSupported ? .ready(status) : .unsupportedFirmware)

        case .setPIN:
            if let id = connectedPeripheral?.identifier {
                if pendingPINIsFactory {
                    clearPINChanged(id)
                } else {
                    markPINChanged(id)
                }
                if let pin = pendingPINToCache {
                    PairingPINStore.save(pin, for: id)
                }
            }
            let isFactoryPIN = pendingPINIsFactory
            let savedPIN = pendingPINToCache
            DispatchQueue.main.async {
                self.showFactoryPINReminder = isFactoryPIN
                self.cachedPairingPIN = savedPIN
            }
            finishSecurity(.pinSaved)

        case .erase:
            if let id = connectedPeripheral?.identifier {
                clearPairingHistory(id)
            }
            // The firmware reboots after acknowledging; suppress auto-reconnect
            // until the user explicitly connects again.
            suppressAutoReconnect = true
            awaitingResetDisconnect = true
            UserDefaults.standard.removeObject(forKey: Keys.lastConnectedUUID)
            UserDefaults.standard.removeObject(forKey: Keys.lastConnectedName)
            cancelReconnect()
            DispatchQueue.main.async {
                self.lastConnectedDeviceName = nil
                self.showFactoryPINReminder = false
                self.cachedPairingPIN = BLESecurityCommand.factoryPIN
            }
            finishSecurity(.erased)
            // Firmware reboots ~500ms after ACKing; disconnect anyway if it stays up.
            bleQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.awaitingResetDisconnect,
                      let peripheral = self.connectedPeripheral else { return }
                self.logger.log("Device did not restart after pairing reset; disconnecting", category: "BLE", level: .warning)
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    private func scheduleSecurityTimeout() {
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.securityScanner != nil else { return }
            self.logger.log("Security response timed out", category: "BLE", level: .warning)
            self.finishSecurity(.failure(.noResponse))
        }
        securityResponseTimeout = timeout
        bleQueue.asyncAfter(deadline: .now() + 5, execute: timeout)
    }

    /// Runs on bleQueue.
    private func finishSecurity(_ state: SecurityState) {
        securityResponseTimeout?.cancel()
        securityResponseTimeout = nil
        if var scanner = securityScanner {
            let remainder = scanner.flush()
            if !remainder.isEmpty { rawDataSubject.send(remainder) }
        }
        securityScanner = nil
        pendingSecurityRequest = nil
        pendingPINIsFactory = false
        pendingPINToCache = nil
        DispatchQueue.main.async { self.securityState = state }
    }

    // MARK: - Pairing Local Hints

    private func markDeviceSeen(_ identifier: UUID) -> Bool {
        var seen = Set(UserDefaults.standard.stringArray(forKey: Keys.pairedDeviceUUIDs) ?? [])
        let firstConnection = !seen.contains(identifier.uuidString)
        seen.insert(identifier.uuidString)
        UserDefaults.standard.set(Array(seen), forKey: Keys.pairedDeviceUUIDs)
        return firstConnection
    }

    private func hasChangedPIN(_ identifier: UUID) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: Keys.pinChangedUUIDs) ?? [])
            .contains(identifier.uuidString)
    }

    private func markPINChanged(_ identifier: UUID) {
        var changed = Set(UserDefaults.standard.stringArray(forKey: Keys.pinChangedUUIDs) ?? [])
        changed.insert(identifier.uuidString)
        UserDefaults.standard.set(Array(changed), forKey: Keys.pinChangedUUIDs)
    }

    private func clearPINChanged(_ identifier: UUID) {
        var changed = Set(UserDefaults.standard.stringArray(forKey: Keys.pinChangedUUIDs) ?? [])
        changed.remove(identifier.uuidString)
        UserDefaults.standard.set(Array(changed), forKey: Keys.pinChangedUUIDs)
    }

    private func clearPairingHistory(_ identifier: UUID) {
        var seen = Set(UserDefaults.standard.stringArray(forKey: Keys.pairedDeviceUUIDs) ?? [])
        seen.remove(identifier.uuidString)
        UserDefaults.standard.set(Array(seen), forKey: Keys.pairedDeviceUUIDs)
        clearPINChanged(identifier)
        // Every caller means the device-side bond was erased, and this
        // firmware's only erase path restores the factory PIN.
        PairingPINStore.save(BLESecurityCommand.factoryPIN, for: identifier)
    }

    /// Clears this app's pairing records. Keeps `knownDeviceUUIDs` so a
    /// renamed device stays discoverable, and keeps `pinChangedUUIDs` because
    /// forgetting the pairing does not reset the PIN on the device.
    static func clearLocalPairingState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.lastConnectedUUID)
        defaults.removeObject(forKey: Keys.lastConnectedName)
        defaults.removeObject(forKey: Keys.pairedDeviceUUIDs)
    }

    func startScanning() {
        if centralManager.state == .poweredOn {
            logger.log("Starting BLE scan", category: "BLE")
            // Unfiltered on purpose: older firmware may not advertise FFF0, and
            // the discovery predicate already rejects unrelated peripherals.
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
        logger.logHex(hexString, message: "Data sent", category: "BLE", level: .debug)
    }

    /// Sends a discrete HID report (click, key, scroll, button state).
    ///
    /// Discrete events are never coalesced. Any accumulated relative movement is
    /// flushed first so the host applies it before the event; if the link is
    /// still busy, the stale movement is dropped instead of delaying the event.
    func sendTouchData(data: Data) {
        guard connectionState == .connected,
              let connectedPeripheral = connectedPeripheral else {
            // ponytail: one-time warning — only if user hasn't dismissed it before
            if !UserDefaults.standard.bool(forKey: "didWarnNoBLEConnection") {
                DispatchQueue.main.async {
                    UserDefaults.standard.set(true, forKey: "didWarnNoBLEConnection")
                    self.showNoConnectionWarning = true
                }
            }
            return
        }

        guard let fff2Characteristic = fff2Characteristic else {
            logger.log("FFF2 characteristic not found", category: "BLE", level: .error)
            return
        }

        guard fff2Characteristic.properties.contains(.writeWithoutResponse) else {
            logger.log("FFF2 characteristic does not support writing", category: "BLE", level: .error)
            return
        }

        hidWriteQueue.async { [weak self] in
            guard let self else { return }
            self.flushPendingMoves()
            self.pendingMoveDx = 0
            self.pendingMoveDy = 0
            connectedPeripheral.writeValue(data, for: fff2Characteristic, type: .withoutResponse)
        }
    }

    /// Queues a relative mouse move.
    ///
    /// Deltas are not clamped: they are coalesced while the link is busy and
    /// split into ±127 CH9329 steps, so fast swipes are never silently lost.
    func sendMouseMove(dx: Int, dy: Int, buttons: UInt8 = 0) {
        guard dx != 0 || dy != 0 else { return }
        guard connectionState == .connected,
              let peripheral = connectedPeripheral,
              let characteristic = fff2Characteristic,
              characteristic.properties.contains(.writeWithoutResponse) else { return }

        hidWriteQueue.async { [weak self] in
            guard let self else { return }

            if buttons != self.pendingMoveButtons {
                // Finish movement that belongs to the previous button state first.
                self.flushPendingMoves()
                if self.pendingMoveDx != 0 || self.pendingMoveDy != 0 {
                    // Link still busy: old-button movement is stale next to a state change.
                    self.pendingMoveDx = 0
                    self.pendingMoveDy = 0
                }
                self.pendingMoveButtons = buttons
            }

            self.pendingMoveDx += dx
            self.pendingMoveDy += dy
            self.pendingMovePeripheral = peripheral
            self.pendingMoveCharacteristic = characteristic
            self.flushPendingMoves()
        }
    }

    /// Consumes one CH9329-sized step (±127) from an accumulated relative delta.
    static func nextMouseStep(dx: inout Int, dy: inout Int) -> (dx: Int8, dy: Int8)? {
        guard dx != 0 || dy != 0 else { return nil }
        let stepX = Int8(max(-127, min(127, dx)))
        let stepY = Int8(max(-127, min(127, dy)))
        dx -= Int(stepX)
        dy -= Int(stepY)
        return (stepX, stepY)
    }

    /// Runs on hidWriteQueue. Sends coalesced movement while the link can accept
    /// unacknowledged writes; the remainder waits for
    /// peripheralIsReadyToSendWriteWithoutResponse.
    private func flushPendingMoves() {
        guard pendingMoveDx != 0 || pendingMoveDy != 0,
              let peripheral = pendingMovePeripheral,
              let characteristic = pendingMoveCharacteristic else { return }

        var sentFrames = 0
        while (pendingMoveDx != 0 || pendingMoveDy != 0),
              peripheral.canSendWriteWithoutResponse {
            guard let step = Self.nextMouseStep(dx: &pendingMoveDx, dy: &pendingMoveDy) else { break }
            let packet = Keymod.buildMouseRel(
                buttons: pendingMoveButtons,
                dx: step.dx,
                dy: step.dy,
                wheel: 0
            )
            peripheral.writeValue(packet, for: characteristic, type: .withoutResponse)
            sentFrames += 1

            if sentFrames >= 32 {
                // Keep the queue responsive; resume when the link drains.
                hidWriteQueue.async { [weak self] in self?.flushPendingMoves() }
                return
            }
        }

        if pendingMoveDx == 0 && pendingMoveDy == 0 {
            pendingMovePeripheral = nil
            pendingMoveCharacteristic = nil
        }
    }

    private func resetPendingMoves() {
        pendingMoveDx = 0
        pendingMoveDy = 0
        pendingMoveButtons = 0
        pendingMovePeripheral = nil
        pendingMoveCharacteristic = nil
    }

    /// Drop queued movement so a reconnection never replays stale deltas.
    private func discardPendingMoves() {
        hidWriteQueue.async { [weak self] in self?.resetPendingMoves() }
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
            if var scanner = renameScanner {
                let result = scanner.feed(data)
                renameScanner = scanner
                if !result.passthrough.isEmpty { rawDataSubject.send(result.passthrough) }
                if let response = result.responses.first {
                    handleRenameResponse(response)
                }
            } else if var scanner = ecmScanner {
                let result = scanner.feed(data)
                ecmScanner = scanner
                if !result.passthrough.isEmpty { rawDataSubject.send(result.passthrough) }
                if let response = result.responses.first {
                    handleECMResponse(response)
                }
            } else if var scanner = securityScanner {
                let result = scanner.feed(data)
                securityScanner = scanner
                if !result.passthrough.isEmpty { rawDataSubject.send(result.passthrough) }
                if let response = result.responses.first {
                    handleSecurityResponse(response)
                }
            } else {
                // Raw data from BLE-Eth tunnel — publish to subscribers
                rawDataSubject.send(data)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.log("Notification state update failed for \(characteristic.uuid): \(error.localizedDescription)", category: "BLE", level: .error)
            guard awaitingPairing else { return }

            // If iOS has just paired (or dropped a stale bond and re-paired), the
            // pending CCCD write still completes with 0x0F and is never retried
            // by the system. Re-subscribe once the security procedure settled.
            if characteristic.uuid == CBUUID(string: "FFF1"),
               isInsufficientEncryption(error),
               pairingNotifyRetries < 1 {
                pairingNotifyRetries += 1
                logger.log("Link not encrypted yet; retrying FFF1 subscription (\(pairingNotifyRetries)/1)", category: "BLE", level: .warning)
                bleQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.awaitingPairing,
                          let fff1 = self.fff1Characteristic else { return }
                    self.connectedPeripheral?.setNotifyValue(true, for: fff1)
                }
                return
            }

            handlePairingFailure(issue: mapPairingError(error))
            return
        }
        logger.log("Notification state for \(characteristic.uuid): \(characteristic.isNotifying ? "enabled" : "disabled")", category: "BLE", level: .success)

        guard characteristic.uuid == CBUUID(string: "FFF1") else { return }
        if characteristic.isNotifying {
            finalizeConnection(peripheral)
        } else if awaitingPairing {
            handlePairingFailure(issue: .authenticationFailed)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let error else { return }
        logger.log("Write failed for \(characteristic.uuid): \(error.localizedDescription)", category: "BLE", level: .error)
        guard awaitingPairing else { return }
        handlePairingFailure(issue: mapPairingError(error))
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        hidWriteQueue.async { [weak self] in
            guard let self,
                  self.pendingMovePeripheral?.identifier == peripheral.identifier else { return }
            self.flushPendingMoves()
        }
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
        discardPendingMoves()

        if peripheral.identifier == connectedPeripheral?.identifier {
            connectedPeripheral = nil
            fff2Characteristic = nil
            fff1Characteristic = nil
        }

        if pendingRenameName != nil {
            if peripheral.identifier == renameRebootIdentifier {
                // Expected firmware reboot after rename: rescan and match by UUID,
                // skipping the normal 1s/2s/4s backoff which would expire mid-boot.
                DispatchQueue.main.async {
                    self.connectedDevices.remove(peripheral.identifier)
                    self.connectionState = .reconnecting
                }
                bleQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.startScanning()
                }
                return
            }
            finishRename(.failure(.disconnected))
        }

        if ecmScanner != nil {
            finishECM(.failure(.disconnected))
        }

        if securityScanner != nil {
            finishSecurity(.failure(.disconnected))
        }

        if awaitingResetDisconnect {
            // Expected reboot after erasing bonds. Keep the result, do not reconnect.
            awaitingResetDisconnect = false
            awaitingPairing = false
            cancelPairingTimeout()
            DispatchQueue.main.async {
                self.connectedDevices.remove(peripheral.identifier)
                self.connectionState = .disconnected
                self.isWaitingForPairing = false
            }
            return
        }

        if awaitingPairing {
            // Half-open link dropped before encryption: surface the reason instead
            // of silently retrying with the same (possibly stale) bond.
            awaitingPairing = false
            cancelPairingTimeout()
            suppressAutoReconnect = true
            let issue = error.map(mapPairingError) ?? .connectionFailed
            if issue == .staleBond {
                // Device-side bond erase also restores the factory PIN.
                clearPairingHistory(peripheral.identifier)
            }
            logger.log("Pairing link dropped before encryption: \(issue)", category: "BLE", level: .error)
            DispatchQueue.main.async {
                self.connectedDevices.remove(peripheral.identifier)
                self.connectionState = .disconnected
                self.isWaitingForPairing = false
                self.isReconnecting = false
                self.pairingIssue = issue
            }
            return
        }

        if let error, isPairingRelatedError(error) {
            // Encryption failed outside the pairing window (e.g. stale bond on an
            // already-connected link). iOS has no unbond API, so stop retrying.
            if isPeerRemovedPairingInformation(error) {
                // Device-side bond erase also restores the factory PIN.
                clearPairingHistory(peripheral.identifier)
            }
            suppressAutoReconnect = true
            logger.log("Pairing-related disconnect: suppressing auto-reconnect", category: "BLE", level: .warning)
            DispatchQueue.main.async {
                self.connectedDevices.remove(peripheral.identifier)
                self.connectionState = .disconnected
                self.isReconnecting = false
            }
            return
        }

        if suppressAutoReconnect {
            logger.log("Auto-reconnect suppressed after pairing failure", category: "BLE", level: .info)
            DispatchQueue.main.async {
                self.connectedDevices.remove(peripheral.identifier)
                self.connectionState = .disconnected
                self.isReconnecting = false
            }
            return
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
            self.bleQueue.async {
                if self.renameRebootIdentifier != nil {
                    // Renamed device still booting: keep scanning until the rename deadline.
                    DispatchQueue.main.async { self.connectionState = .reconnecting }
                    self.startScanning()
                } else {
                    DispatchQueue.main.async {
                        self.connectionState = .disconnected
                        self.isReconnecting = false
                    }
                }
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