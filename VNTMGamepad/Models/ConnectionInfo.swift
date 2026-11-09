//
//  ConnectionInfo.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//

import Foundation

// MARK: - Connection Type

/// Supported wireless physical transport mediums for gamepad data exchange.
public enum ConnectionType: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Bluetooth Low Energy (CoreBluetooth / GATT).
    case bluetooth
    /// Local Wi-Fi network (TCP/UDP socket streaming).
    case wifi

    public var id: String { rawValue }

    /// User-facing descriptive transport title.
    public var displayName: String {
        switch self {
        case .bluetooth: return "Bluetooth Low Energy"
        case .wifi: return "Wi-Fi (UDP / TCP)"
        }
    }

    /// SF Symbol icon associated with the connection transport.
    public var symbolName: String {
        switch self {
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .wifi: return "wifi"
        }
    }
}

// MARK: - Connection Status

/// Lifecycle and handshake states for connection managers.
public enum ConnectionStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    /// No active connection or pending handshake.
    case disconnected
    /// Searching for compatible companion servers or BLE peripherals.
    case scanning
    /// Establishing socket or GATT channel with remote host.
    case connecting
    /// Active, verified stream ready for low-latency state transmission.
    case connected
    /// Fatal error, protocol mismatch, or unexpected disconnection occurred.
    case error

    public var id: String { rawValue }

    /// Human-readable description of current state.
    public var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }

    /// Convenience flag indicating whether gamepad data can be currently sent.
    public var isConnected: Bool {
        self == .connected
    }
}

// MARK: - Device Info

/// Discovered or remembered host device metadata.
public struct DeviceInfo: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Unique identifier: UUID string for BLE peripheral or IP address/hostname for Wi-Fi.
    public var id: String

    /// Advertised or resolved companion hostname/device name.
    public var name: String

    /// Transport used to connect to this device.
    public var connectionType: ConnectionType

    /// Timestamp of most recent successful connection session.
    public var lastConnected: Date?

    /// Received signal strength indication (RSSI in dBm for BLE, or quality percentage).
    public var signalStrength: Int?

    public init(
        id: String,
        name: String,
        connectionType: ConnectionType,
        lastConnected: Date? = nil,
        signalStrength: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.connectionType = connectionType
        self.lastConnected = lastConnected
        self.signalStrength = signalStrength
    }

    /// Formatted display string for signal strength.
    public var formattedSignalStrength: String {
        guard let signal = signalStrength else { return "N/A" }
        switch connectionType {
        case .bluetooth:
            return "\(signal) dBm"
        case .wifi:
            return "\(signal)%"
        }
    }
}

// MARK: - Connection Metrics

/// Live diagnostics, latency benchmarks, and packet telemetry.
public struct ConnectionMetrics: Codable, Equatable, Sendable {
    /// Measured round-trip ping time in milliseconds.
    public var latency: Double

    /// Live link quality indicator (dBm for BLE or percentage for Wi-Fi).
    public var signalStrength: Int

    /// Total count of controller state packets successfully transmitted.
    public var packetsSent: UInt64

    /// Total count of transmitted packets that failed or were unacknowledged.
    public var packetsLost: UInt64

    /// Total continuous active connection duration in seconds.
    public var connectionUptime: TimeInterval

    /// Percentage rate of dropped packets calculated from total attempted transmissions.
    public var packetLossRate: Double {
        let total = packetsSent + packetsLost
        guard total > 0 else { return 0.0 }
        return (Double(packetsLost) / Double(total)) * 100.0
    }

    /// Standard empty telemetry metric baseline.
    public static let zero = ConnectionMetrics()

    public init(
        latency: Double = 0.0,
        signalStrength: Int = 0,
        packetsSent: UInt64 = 0,
        packetsLost: UInt64 = 0,
        connectionUptime: TimeInterval = 0.0
    ) {
        self.latency = latency
        self.signalStrength = signalStrength
        self.packetsSent = packetsSent
        self.packetsLost = packetsLost
        self.connectionUptime = connectionUptime
    }
}
