//
//  ConnectionViewModel.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//  MVVM Architecture with Combine Framework
//

import Foundation
import SwiftUI
import Combine
import os.log

/// ViewModel responsible for managing peripheral discovery, connection establishment,
/// state synchronization across Bluetooth LE and local Wi-Fi transports, telemetry metrics,
/// and automated fault recovery using exponential backoff reconnection.
@MainActor
public final class ConnectionViewModel: ObservableObject {

    // MARK: - Constants

    /// Key for storing preferred transport in UserDefaults.
    private static let preferredConnectionTypeKey = "preferredConnectionType"

    /// Key for persisting auto-reconnect preference.
    private static let autoReconnectKey = "vntm.connection.autoReconnect"

    /// Key for persisting last connected device metadata.
    private static let lastConnectedDeviceKey = "lastConnectedDevice"

    /// Exponential backoff delay steps in seconds.
    private static let backoffDelays: [TimeInterval] = [1.0, 2.0, 4.0, 8.0, 16.0, 30.0]

    /// Maximum consecutive auto-reconnect attempts before giving up.
    private static let maxReconnectAttempts = 8

    // MARK: - Published Properties

    /// Active wireless transport medium being scanned or connected (Bluetooth LE or Wi-Fi).
    @Published public var connectionType: ConnectionType {
        didSet {
            userDefaults.set(connectionType.rawValue, forKey: Self.preferredConnectionTypeKey)
            updateDiscoveredDevices()
            logger.debug("Preferred connection type updated to: \(self.connectionType.displayName)")
        }
    }

    /// Unified connection status representing the current lifecycle stage of the active transport.
    @Published public var status: ConnectionStatus = .disconnected

    /// List of discovered companion devices filtered by the active `connectionType`.
    @Published public var discoveredDevices: [DeviceInfo] = []

    /// Companion device currently targeted, connecting, or actively streaming.
    @Published public var selectedDevice: DeviceInfo? = nil

    /// Real-time live connection health diagnostics, throughput, ping, and packet loss metrics.
    @Published public var metrics: ConnectionMetrics = .zero

    /// User-facing localized error or warning message describing transport faults.
    @Published public var errorMessage: String? = nil

    /// Whether the ViewModel should automatically attempt to re-establish dropped sessions.
    @Published public var isAutoReconnect: Bool = true {
        didSet {
            userDefaults.set(isAutoReconnect, forKey: Self.autoReconnectKey)
            if !isAutoReconnect {
                cancelScheduledReconnect()
            }
        }
    }

    // MARK: - Injected Dependencies

    private let bluetoothService: BluetoothService
    private let wiFiService: WiFiService
    private let userDefaults: UserDefaults

    // MARK: - Private State

    /// Retained Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Tracks whether a disconnection was intentionally requested by user action.
    private var isManualDisconnect: Bool = false

    /// Current attempt count for exponential backoff recovery.
    private var reconnectAttemptCount: Int = 0

    /// Scheduled task item executing delayed reconnection.
    private var reconnectWorkItem: DispatchWorkItem?

    /// Periodic telemetry timer updating uptime and latency metrics every second.
    private var metricsTimer: AnyCancellable?

    /// Continuous uptime timer timestamp reference.
    private var connectionStartTime: Date?

    /// Native unified system logger.
    private let logger = Logger(subsystem: "com.vntm.gamepad", category: "ConnectionViewModel")

    // MARK: - Initialization

    /// Initializes a new instance of ConnectionViewModel.
    ///
    /// - Parameters:
    ///   - bluetoothService: Low-energy Bluetooth communication transport.
    ///   - wiFiService: Local Wi-Fi network socket transport.
    ///   - userDefaults: Key-value persistence interface (defaults to `.standard`).
    public init(
        bluetoothService: BluetoothService,
        wiFiService: WiFiService,
        userDefaults: UserDefaults = .standard
    ) {
        self.bluetoothService = bluetoothService
        self.wiFiService = wiFiService
        self.userDefaults = userDefaults

        // 1. Restore preferred transport type from UserDefaults
        if let savedTypeString = userDefaults.string(forKey: Self.preferredConnectionTypeKey),
           let savedType = ConnectionType(rawValue: savedTypeString) {
            self.connectionType = savedType
        } else {
            self.connectionType = .bluetooth
        }

        // 2. Restore auto-reconnect setting
        if userDefaults.object(forKey: Self.autoReconnectKey) != nil {
            self.isAutoReconnect = userDefaults.bool(forKey: Self.autoReconnectKey)
        } else {
            self.isAutoReconnect = true
        }

        // 3. Restore last connected device if available
        if let savedDeviceData = userDefaults.data(forKey: Self.lastConnectedDeviceKey),
           let savedDevice = try? JSONDecoder().decode(DeviceInfo.self, from: savedDeviceData) {
            self.selectedDevice = savedDevice
        }

        setupSubscriptions()
        setupMetricsTimer()
        logger.info("ConnectionViewModel initialized. Transport: \(self.connectionType.displayName), AutoReconnect: \(self.isAutoReconnect)")
    }

    deinit {
        cancelScheduledReconnect()
        metricsTimer?.cancel()
    }

    // MARK: - Combine Setup

    /// Subscribes to dependency transport publishers to maintain unified status and device collections.
    private func setupSubscriptions() {
        // Observe Bluetooth service state changes
        bluetoothService.$connectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] btStatus in
                self?.handleTransportStatusChange(transport: .bluetooth, status: btStatus)
            }
            .store(in: &cancellables)

        bluetoothService.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.connectionType == .bluetooth else { return }
                self.updateDiscoveredDevices()
            }
            .store(in: &cancellables)

        bluetoothService.$connectedDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                guard let self = self, self.connectionType == .bluetooth, let device = device else { return }
                self.selectedDevice = device
                self.saveLastConnectedDevice(device)
            }
            .store(in: &cancellables)

        bluetoothService.$rssi
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rssi in
                guard let self = self, self.connectionType == .bluetooth else { return }
                self.metrics.signalStrength = rssi
            }
            .store(in: &cancellables)

        // Observe Wi-Fi service state changes
        wiFiService.$connectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] wifiStatus in
                self?.handleTransportStatusChange(transport: .wifi, status: wifiStatus)
            }
            .store(in: &cancellables)

        wiFiService.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.connectionType == .wifi else { return }
                self.updateDiscoveredDevices()
            }
            .store(in: &cancellables)

        wiFiService.$connectedDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                guard let self = self, self.connectionType == .wifi, let device = device else { return }
                self.selectedDevice = device
                self.saveLastConnectedDevice(device)
            }
            .store(in: &cancellables)

        wiFiService.$latency
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latency in
                guard let self = self, self.connectionType == .wifi else { return }
                self.metrics.latency = latency
            }
            .store(in: &cancellables)
    }

    /// Handles transport lifecycle transitions and orchestrates auto-reconnect behavior.
    private func handleTransportStatusChange(transport: ConnectionType, status: ConnectionStatus) {
        // Only update primary status if it relates to the active transport
        guard transport == connectionType else { return }

        let previousStatus = self.status
        self.status = status

        switch status {
        case .connected:
            errorMessage = nil
            reconnectAttemptCount = 0
            cancelScheduledReconnect()
            isManualDisconnect = false
            connectionStartTime = Date()
            logger.info("Successfully connected to \(transport.displayName) device.")

        case .disconnected:
            connectionStartTime = nil
            if !isManualDisconnect && isAutoReconnect && selectedDevice != nil && previousStatus == .connected {
                logger.warning("Unexpected disconnection detected on \(transport.displayName). Triggering auto-reconnect backoff.")
                triggerAutoReconnect()
            }

        case .error:
            connectionStartTime = nil
            errorMessage = "Connection error occurred on \(transport.displayName)."
            if !isManualDisconnect && isAutoReconnect && selectedDevice != nil {
                triggerAutoReconnect()
            }

        case .scanning, .connecting:
            errorMessage = nil
        }
    }

    /// Synchronizes the published `discoveredDevices` list from the active transport service.
    private func updateDiscoveredDevices() {
        switch connectionType {
        case .bluetooth:
            discoveredDevices = bluetoothService.discoveredDevices
        case .wifi:
            discoveredDevices = wiFiService.discoveredDevices
        }
    }

    // MARK: - Public Actions

    /// Starts scanning for nearby companion hosts using the specified transport medium.
    ///
    /// - Parameter type: The wireless transport to search across (defaults to currently selected `connectionType`).
    public func startScanning(type: ConnectionType? = nil) {
        if let type = type {
            self.connectionType = type
        }

        errorMessage = nil
        cancelScheduledReconnect()

        switch connectionType {
        case .bluetooth:
            wiFiService.stopDiscovery()
            bluetoothService.startScanning()
            status = .scanning
            logger.info("Started Bluetooth scanning.")

        case .wifi:
            bluetoothService.stopScanning()
            wiFiService.startDiscovery()
            status = .scanning
            logger.info("Started Bonjour Wi-Fi discovery.")
        }

        updateDiscoveredDevices()
    }

    /// Stops any ongoing peripheral scanning or service discovery across all transports.
    public func stopScanning() {
        bluetoothService.stopScanning()
        wiFiService.stopDiscovery()

        if status == .scanning {
            let isAnyConnected = bluetoothService.connectionStatus == .connected || wiFiService.connectionStatus == .connected
            status = isAnyConnected ? .connected : .disconnected
        }

        logger.info("Scanning stopped.")
    }

    /// Establishes a connection with the specified companion device.
    ///
    /// - Parameter device: The target companion device metadata.
    public func connect(to device: DeviceInfo) {
        cancelScheduledReconnect()
        isManualDisconnect = false
        reconnectAttemptCount = 0
        errorMessage = nil
        selectedDevice = device
        connectionType = device.connectionType
        saveLastConnectedDevice(device)

        status = .connecting
        logger.info("Initiating connection to \(device.name) via \(device.connectionType.displayName)...")

        switch device.connectionType {
        case .bluetooth:
            wiFiService.disconnect()
            bluetoothService.connect(to: device)

        case .wifi:
            bluetoothService.disconnect()
            wiFiService.connect(to: device)
        }
    }

    /// Disconnects from the current peer device and halts any automated reconnection.
    public func disconnect() {
        isManualDisconnect = true
        cancelScheduledReconnect()
        reconnectAttemptCount = 0
        connectionStartTime = nil

        bluetoothService.disconnect()
        wiFiService.disconnect()

        status = .disconnected
        metrics = .zero
        logger.info("Disconnected by user.")
    }

    /// Toggles the automated reconnection feature on or off.
    public func toggleAutoReconnect() {
        isAutoReconnect.toggle()
        logger.info("Auto-reconnect toggled: \(self.isAutoReconnect)")
    }

    /// Clears and refreshes the discovered device list for the active transport.
    public func refreshDevices() {
        discoveredDevices.removeAll()
        startScanning(type: connectionType)
    }

    // MARK: - Auto-Reconnect Logic with Exponential Backoff

    /// Schedules an automated reconnection attempt using an exponential backoff cadence.
    private func triggerAutoReconnect() {
        guard isAutoReconnect, !isManualDisconnect, let targetDevice = selectedDevice else {
            return
        }

        guard reconnectAttemptCount < Self.maxReconnectAttempts else {
            logger.error("Auto-reconnect failed: exceeded maximum attempts (\(Self.maxReconnectAttempts)).")
            errorMessage = "Auto-reconnect failed after \(Self.maxReconnectAttempts) attempts. Please connect manually."
            status = .error
            return
        }

        let delayIndex = min(reconnectAttemptCount, Self.backoffDelays.count - 1)
        let delay = Self.backoffDelays[delayIndex]
        reconnectAttemptCount += 1

        logger.info("Scheduling auto-reconnect attempt \(self.reconnectAttemptCount) in \(delay) seconds...")
        status = .connecting
        errorMessage = "Reconnecting to \(targetDevice.name) (attempt \(reconnectAttemptCount)/\(Self.maxReconnectAttempts))..."

        cancelScheduledReconnect()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isManualDisconnect, self.isAutoReconnect else { return }
            self.logger.info("Executing auto-reconnect attempt \(self.reconnectAttemptCount)...")
            switch targetDevice.connectionType {
            case .bluetooth:
                self.bluetoothService.connect(to: targetDevice)
            case .wifi:
                self.wiFiService.connect(to: targetDevice)
            }
        }

        self.reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Cancels any scheduled pending auto-reconnect execution.
    private func cancelScheduledReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    // MARK: - Metrics & Diagnostics

    /// Configures periodic background timer tracking connection duration and telemetry.
    private func setupMetricsTimer() {
        metricsTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateMetricsTelemetry()
            }
    }

    /// Updates live connection duration and packet benchmarks.
    private func updateMetricsTelemetry() {
        guard status == .connected else { return }

        if let startTime = connectionStartTime {
            metrics.connectionUptime = Date().timeIntervalSince(startTime)
        }

        // Signal strength updates
        switch connectionType {
        case .bluetooth:
            metrics.signalStrength = bluetoothService.rssi
        case .wifi:
            metrics.signalStrength = wiFiService.connectedDevice?.signalStrength ?? 100
        }
    }

    // MARK: - Persistence

    /// Persists the last successfully connected companion device metadata in UserDefaults.
    private func saveLastConnectedDevice(_ device: DeviceInfo) {
        if let encoded = try? JSONEncoder().encode(device) {
            userDefaults.set(encoded, forKey: Self.lastConnectedDeviceKey)
        }
    }
}
