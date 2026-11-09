//
//  BluetoothService.swift
//  VNTM Gamepad
//
//  CoreBluetooth-powered transport service handling BLE central lifecycle,
//  discovery, connection management, auto-reconnection with exponential backoff,
//  background restoration, and high-frequency state streaming.
//

import Foundation
import CoreBluetooth
import Combine
import os.log

/// Service responsible for Bluetooth Low Energy communication with the VNTM companion.
///
/// Manages peripheral scanning, connection state, service and characteristic discovery,
/// background preservation/restoration, and reliable low-latency packet dispatch.
public final class BluetoothService: NSObject, ObservableObject {

    // MARK: - Constants

    /// Custom BLE Service UUID for VNTM Gamepad.
    public static let serviceUUID = CBUUID(string: "VNTM-GP00-0001-0000-000000000000")

    /// Custom BLE Characteristic UUID for VNTM Gamepad state packets and commands.
    public static let characteristicUUID = CBUUID(string: "VNTM-GP00-0001-0000-000000000001")

    /// Restoration identifier used by CoreBluetooth state preservation.
    private static let restoreIdentifier = "com.vntm.gamepad.bluetooth.central"

    /// Key for persisting the last connected peripheral UUID in UserDefaults.
    private static let lastConnectedDeviceKey = "vntm.bluetooth.lastConnectedDeviceUUID"

    /// Exponential backoff steps in seconds: 1s, 2s, 4s, 8s, max 30s.
    private static let backoffDelays: [TimeInterval] = [1.0, 2.0, 4.0, 8.0, 16.0, 30.0]

    // MARK: - Published Properties

    /// Whether Bluetooth hardware is powered on and authorized.
    @Published public private(set) var isAvailable: Bool = false

    /// Whether the central manager is actively scanning for peripherals.
    @Published public private(set) var isScanning: Bool = false

    /// The current connection state of the Bluetooth transport.
    @Published public private(set) var connectionStatus: ConnectionStatus = .disconnected

    /// List of discovered VNTM Gamepad peripherals.
    @Published public private(set) var discoveredDevices: [DeviceInfo] = []

    /// The currently connected peer device metadata, if any.
    @Published public private(set) var connectedDevice: DeviceInfo? = nil

    /// The latest received signal strength indicator (RSSI) value in dBm.
    @Published public private(set) var rssi: Int = 0

    // MARK: - Private Properties

    /// The underlying CoreBluetooth central manager.
    private var centralManager: CBCentralManager!

    /// The currently connected or connecting peripheral instance.
    private var activePeripheral: CBPeripheral?

    /// The discovered state transfer characteristic on the active peripheral.
    private var targetCharacteristic: CBCharacteristic?

    /// Retained references to discovered peripherals mapped by their identifier.
    private var peripheralsMap: [UUID: CBPeripheral] = [:]

    /// Mapping of peripheral identifiers to their latest DeviceInfo representation.
    private var devicesMap: [UUID: DeviceInfo] = [:]

    /// Flag tracking whether the disconnection was explicitly requested by the user.
    private var isIntentionalDisconnect: Bool = false

    /// Current attempt index for exponential backoff reconnection.
    private var reconnectAttemptCount: Int = 0

    /// Timer task for scheduling delayed reconnect attempts.
    private var reconnectWorkItem: DispatchWorkItem?

    /// Periodic timer for polling RSSI on active peripheral.
    private var rssiTimer: AnyCancellable?

    /// Storage interface for saving/restoring last connected peripheral identifier.
    private let userDefaults: UserDefaults

    /// Native unified logger.
    private let logger = Logger(subsystem: "com.vntm.gamepad", category: "Bluetooth")

    // MARK: - Initialization

    /// Initializes a new instance of BluetoothService.
    /// - Parameter userDefaults: Key-value storage for peripheral restoration (defaults to `.standard`).
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        super.init()

        // Configure central manager with background state preservation options.
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier,
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: options)

        AppLog.info("BluetoothService initialized with restore identifier: \(Self.restoreIdentifier)", category: .bluetooth)
    }

    deinit {
        stopRssiPolling()
        reconnectWorkItem?.cancel()
        if centralManager.isScanning {
            centralManager.stopScan()
        }
    }

    // MARK: - Public API

    /// Starts scanning for nearby VNTM Gamepad BLE peripherals.
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot start scanning: Bluetooth is not powered on (state: \(self.centralManager.state.rawValue))")
            AppLog.warning("Cannot scan: Bluetooth not ready.", category: .bluetooth)
            return
        }

        guard !isScanning else {
            logger.debug("Scan already in progress.")
            return
        }

        isScanning = true
        connectionStatus = .scanning
        discoveredDevices.removeAll()
        peripheralsMap.removeAll()
        devicesMap.removeAll()

        logger.info("Starting scan for VNTM peripherals with service UUID: \(Self.serviceUUID.uuidString)")
        AppLog.info("Scanning for VNTM Gamepad devices...", category: .bluetooth)

        // Scan for the dedicated VNTM service UUID with duplicate filtering.
        centralManager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// Stops scanning for BLE peripherals.
    public func stopScanning() {
        guard isScanning else { return }

        logger.info("Stopping BLE scan.")
        AppLog.info("Stopped BLE scan.", category: .bluetooth)
        centralManager.stopScan()
        isScanning = false

        if connectionStatus == .scanning {
            connectionStatus = activePeripheral != nil ? .connected : .disconnected
        }
    }

    /// Connects to a specific discovered device.
    /// - Parameter device: The `DeviceInfo` describing the target peripheral.
    public func connect(to device: DeviceInfo) {
        guard let uuid = UUID(uuidString: device.id),
              let peripheral = peripheralsMap[uuid] else {
            logger.error("Peripheral not found in discovery map for id: \(device.id)")
            AppLog.error("Cannot connect: peripheral \(device.id) not found in discovered list.", category: .bluetooth)
            connectionStatus = .error
            return
        }

        stopScanning()
        cancelPendingReconnect()
        isIntentionalDisconnect = false
        reconnectAttemptCount = 0

        connectPeripheral(peripheral, name: device.name)
    }

    /// Disconnects the active peripheral connection and stops auto-reconnect.
    public func disconnect() {
        isIntentionalDisconnect = true
        cancelPendingReconnect()
        stopRssiPolling()

        if let peripheral = activePeripheral {
            logger.info("Disconnecting active peripheral: \(peripheral.name ?? peripheral.identifier.uuidString)")
            AppLog.info("Disconnecting from BLE device: \(peripheral.name ?? "VNTM Companion")", category: .bluetooth)
            centralManager.cancelPeripheralConnection(peripheral)
        } else {
            connectionStatus = .disconnected
            connectedDevice = nil
        }
    }

    /// Transmits raw data to the connected companion peripheral.
    /// - Parameter data: State packet or command bytes to send.
    public func send(_ data: Data) {
        guard let peripheral = activePeripheral,
              let characteristic = targetCharacteristic,
              connectionStatus == .connected else {
            logger.warning("Drop send: peripheral not connected or characteristic unavailable.")
            return
        }

        // Favor writeWithoutResponse for high-frequency low-latency controller input packets.
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse

        peripheral.writeValue(data, for: characteristic, type: writeType)
    }

    // MARK: - Internal Connection & Reconnect Logic

    /// Internal method to initiate connection to a peripheral.
    private func connectPeripheral(_ peripheral: CBPeripheral, name: String? = nil) {
        activePeripheral = peripheral
        peripheral.delegate = self
        connectionStatus = .connecting

        let displayName = name ?? peripheral.name ?? "VNTM Gamepad"
        logger.info("Connecting to peripheral: \(displayName) [\(peripheral.identifier.uuidString)]")
        AppLog.info("Connecting to \(displayName)...", category: .bluetooth)

        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ])
    }

    /// Schedules an auto-reconnect attempt using exponential backoff.
    private func scheduleAutoReconnect() {
        guard !isIntentionalDisconnect else {
            logger.debug("Skipping auto-reconnect: disconnection was intentional.")
            return
        }

        guard let lastIdString = userDefaults.string(forKey: Self.lastConnectedDeviceKey),
              let lastUUID = UUID(uuidString: lastIdString) else {
            logger.debug("No previously connected device UUID found for auto-reconnect.")
            return
        }

        let delayIndex = min(reconnectAttemptCount, Self.backoffDelays.count - 1)
        let delay = Self.backoffDelays[delayIndex]
        reconnectAttemptCount += 1

        logger.info("Scheduling auto-reconnect attempt #\(self.reconnectAttemptCount) in \(delay)s for \(lastUUID.uuidString)")
        AppLog.info("Scheduling BLE reconnect in \(Int(delay))s (attempt \(self.reconnectAttemptCount))...", category: .bluetooth)

        connectionStatus = .connecting

        reconnectWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isIntentionalDisconnect else { return }
            self.executeReconnect(for: lastUUID)
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Executes a reconnect attempt by retrieving or scanning for the peripheral.
    private func executeReconnect(for uuid: UUID) {
        guard centralManager.state == .poweredOn else {
            logger.warning("Auto-reconnect deferred: Bluetooth is not powered on.")
            return
        }

        // Try retrieving already-known peripheral by identifier
        let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = knownPeripherals.first {
            logger.info("Retrieved known peripheral for auto-reconnect: \(peripheral.identifier.uuidString)")
            peripheralsMap[uuid] = peripheral
            connectPeripheral(peripheral)
        } else {
            // Otherwise, start scanning for it
            logger.info("Peripheral not in system cache, starting scan to reconnect...")
            startScanning()
        }
    }

    /// Cancels any scheduled reconnect timer.
    private func cancelPendingReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    /// Starts periodic RSSI reading while connected.
    private func startRssiPolling() {
        stopRssiPolling()
        rssiTimer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self,
                      let peripheral = self.activePeripheral,
                      self.connectionStatus == .connected else { return }
                peripheral.readRSSI()
            }
    }

    /// Stops RSSI polling timer.
    private func stopRssiPolling() {
        rssiTimer?.cancel()
        rssiTimer = nil
    }

    /// Persists last connected peripheral identifier to UserDefaults.
    private func saveLastConnectedDevice(_ uuid: UUID) {
        userDefaults.set(uuid.uuidString, forKey: Self.lastConnectedDeviceKey)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothService: CBCentralManagerDelegate {

    /// Invoked whenever the central manager's state is updated.
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isAvailable = (central.state == .poweredOn)

            switch central.state {
            case .poweredOn:
                self.logger.info("CoreBluetooth state: poweredOn")
                AppLog.info("Bluetooth powered on.", category: .bluetooth)
                // Attempt auto-reconnect to last device if previously connected
                if !self.isIntentionalDisconnect && self.activePeripheral == nil {
                    self.scheduleAutoReconnect()
                }

            case .poweredOff:
                self.logger.warning("CoreBluetooth state: poweredOff")
                AppLog.warning("Bluetooth powered off.", category: .bluetooth)
                self.handleDisconnectionCleanup(error: nil)

            case .resetting:
                self.logger.warning("CoreBluetooth state: resetting")
                AppLog.warning("Bluetooth resetting.", category: .bluetooth)

            case .unauthorized:
                self.logger.error("CoreBluetooth state: unauthorized")
                AppLog.error("Bluetooth permission denied.", category: .bluetooth)
                self.connectionStatus = .error

            case .unsupported:
                self.logger.error("CoreBluetooth state: unsupported")
                AppLog.error("Bluetooth LE unsupported on this device.", category: .bluetooth)
                self.connectionStatus = .error

            case .unknown:
                self.logger.debug("CoreBluetooth state: unknown")

            @unknown default:
                break
            }
        }
    }

    /// Invoked when central manager discovers a peripheral while scanning.
    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any],
                               rssi RSSI: NSNumber) {
        let uuid = peripheral.identifier
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "VNTM Gamepad"
        let signalStrength = RSSI.intValue

        peripheralsMap[uuid] = peripheral

        let deviceInfo = DeviceInfo(
            id: uuid.uuidString,
            name: name,
            connectionType: .bluetooth,
            lastConnected: nil,
            signalStrength: signalStrength
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.devicesMap[uuid] = deviceInfo
            self.discoveredDevices = Array(self.devicesMap.values)

            self.logger.debug("Discovered BLE peripheral: \(name) [\(uuid.uuidString)] RSSI: \(signalStrength)")

            // Check if this matches pending auto-reconnect target
            if let lastId = self.userDefaults.string(forKey: Self.lastConnectedDeviceKey),
               lastId == uuid.uuidString,
               !self.isIntentionalDisconnect,
               self.activePeripheral == nil {
                self.logger.info("Discovered auto-reconnect target: \(name), connecting immediately.")
                self.stopScanning()
                self.connectPeripheral(peripheral, name: name)
            }
        }
    }

    /// Invoked when a connection is successfully established with a peripheral.
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Successfully connected to peripheral: \(peripheral.name ?? peripheral.identifier.uuidString)")
        AppLog.info("Connected to BLE device: \(peripheral.name ?? "VNTM Companion")", category: .bluetooth)

        // Reset reconnect attempts upon connection
        reconnectAttemptCount = 0
        cancelPendingReconnect()
        saveLastConnectedDevice(peripheral.identifier)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectedDevice = DeviceInfo(
                id: peripheral.identifier.uuidString,
                name: peripheral.name ?? "VNTM Gamepad",
                connectionType: .bluetooth,
                lastConnected: Date(),
                signalStrength: self.rssi
            )
        }

        // Discover custom VNTM service
        peripheral.discoverServices([Self.serviceUUID])
        startRssiPolling()
    }

    /// Invoked when the central manager fails to create a connection with a peripheral.
    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        let errMessage = error?.localizedDescription ?? "Unknown failure"
        logger.error("Failed to connect to peripheral: \(peripheral.identifier.uuidString). Error: \(errMessage)")
        AppLog.error("Failed to connect to BLE device: \(errMessage)", category: .bluetooth)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectionStatus = .error
            self.activePeripheral = nil
            self.connectedDevice = nil
            self.scheduleAutoReconnect()
        }
    }

    /// Invoked when an existing connection with a peripheral is disconnected.
    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        let wasIntentional = isIntentionalDisconnect
        if let error = error {
            logger.warning("Peripheral disconnected with error: \(error.localizedDescription)")
            AppLog.warning("BLE disconnected unexpectedly: \(error.localizedDescription)", category: .bluetooth)
        } else {
            logger.info("Peripheral disconnected cleanly.")
            AppLog.info("BLE disconnected.", category: .bluetooth)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.handleDisconnectionCleanup(error: error)

            if !wasIntentional {
                self.scheduleAutoReconnect()
            }
        }
    }

    /// Restores central manager state when launched in the background.
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        logger.info("CoreBluetooth willRestoreState triggered.")
        AppLog.info("Restoring background Bluetooth state...", category: .bluetooth)

        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                peripheralsMap[peripheral.identifier] = peripheral
                if peripheral.state == .connected || peripheral.state == .connecting {
                    activePeripheral = peripheral
                    peripheral.delegate = self
                    connectionStatus = peripheral.state == .connected ? .connected : .connecting
                    logger.info("Restored active peripheral: \(peripheral.identifier.uuidString)")
                }
            }
        }
    }

    /// Cleans up state after a disconnection occurs.
    private func handleDisconnectionCleanup(error: Error?) {
        stopRssiPolling()
        activePeripheral = nil
        targetCharacteristic = nil
        connectedDevice = nil
        rssi = 0
        connectionStatus = (error != nil) ? .error : .disconnected
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {

    /// Invoked upon discovery of services on the peripheral.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logger.error("Error discovering services: \(error.localizedDescription)")
            AppLog.error("BLE service discovery failed: \(error.localizedDescription)", category: .bluetooth)
            DispatchQueue.main.async { [weak self] in
                self?.connectionStatus = .error
            }
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            logger.warning("No services discovered on peripheral.")
            return
        }

        for service in services where service.uuid == Self.serviceUUID {
            logger.info("Discovered VNTM service: \(service.uuid.uuidString). Discovering characteristics...")
            peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
        }
    }

    /// Invoked upon discovery of characteristics for a service.
    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        if let error = error {
            logger.error("Error discovering characteristics: \(error.localizedDescription)")
            AppLog.error("BLE characteristic discovery failed: \(error.localizedDescription)", category: .bluetooth)
            DispatchQueue.main.async { [weak self] in
                self?.connectionStatus = .error
            }
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics where characteristic.uuid == Self.characteristicUUID {
            logger.info("Found VNTM state characteristic: \(characteristic.uuid.uuidString)")
            AppLog.info("VNTM BLE characteristic linked and ready.", category: .bluetooth)

            self.targetCharacteristic = characteristic

            // Subscribe to notify/indicate if supported
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }

            DispatchQueue.main.async { [weak self] in
                self?.connectionStatus = .connected
            }
        }
    }

    /// Invoked when characteristic value is updated or notification is received.
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error = error {
            logger.error("Error updating characteristic value: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else { return }
        logger.debug("Received \(data.count) bytes on characteristic \(characteristic.uuid.uuidString)")
    }

    /// Invoked when write with response completes.
    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error = error {
            logger.error("Error writing characteristic value: \(error.localizedDescription)")
        }
    }

    /// Invoked when peripheral RSSI is read.
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.rssi = RSSI.intValue
            if var current = self.connectedDevice {
                current.signalStrength = RSSI.intValue
                self.connectedDevice = current
            }
        }
    }
}
