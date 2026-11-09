//
//  CommunicationProtocol.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//

import Foundation

// MARK: - Constants

/// Core timing, retry, and timeout constants governing communication channels.
public enum CommunicationConstants {
    /// Heartbeat transmission cadence (0.1 seconds / 100 ms / 10 Hz).
    public static let heartbeatInterval: TimeInterval = 0.1

    /// Timeout budget when attempting to establish a channel connection (10.0 seconds).
    public static let connectionTimeout: TimeInterval = 10.0

    /// Maximum consecutive connection retry attempts before escalating to failure (5).
    public static let maxRetries: Int = 5

    /// Backoff delay between consecutive reconnection attempts (2.0 seconds).
    public static let reconnectDelay: TimeInterval = 2.0
}

// MARK: - Connection Type

/// Physical or transport medium utilized by a communication channel.
public enum ConnectionType: String, CaseIterable, Codable, Sendable {
    case bluetooth = "Bluetooth"
    case wifi      = "Wi-Fi"

    /// User-facing display title.
    public var displayName: String { rawValue }

    /// SF Symbol icon name appropriate for SwiftUI display.
    public var systemImage: String {
        switch self {
        case .bluetooth:
            return "antenna.radiowaves.left.and.right"
        case .wifi:
            return "wifi"
        }
    }
}

// MARK: - Connection Error

/// Specific errors that can occur during connection lifecycle, packet transfer, or transport operations.
public enum ConnectionError: Error, LocalizedError, Equatable, Sendable {
    case timeout
    case refused
    case lost
    case encryption
    case invalidPacket
    case bluetoothUnavailable
    case wifiUnavailable
    case unknown(String)

    /// Human-readable explanation suitable for user alerts and diagnostics.
    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "The connection timed out waiting for a host response."
        case .refused:
            return "The connection was refused by the companion host."
        case .lost:
            return "The connection to the companion host was lost."
        case .encryption:
            return "Encryption or decryption negotiation failed."
        case .invalidPacket:
            return "An invalid packet was received (header mismatch or corrupted checksum)."
        case .bluetoothUnavailable:
            return "Bluetooth is powered off or unavailable on this device."
        case .wifiUnavailable:
            return "Wi-Fi is disconnected or local network access is unavailable."
        case .unknown(let message):
            return message
        }
    }

    /// Short diagnostic recovery suggestion.
    public var recoverySuggestion: String? {
        switch self {
        case .timeout, .refused:
            return "Ensure the VNTM Companion application is running on your PC."
        case .lost:
            return "Check your wireless connection and move closer to the host."
        case .encryption:
            return "Verify that the encryption passphrase matches the companion host."
        case .invalidPacket:
            return "Ensure both the iOS app and PC companion are updated to compatible versions."
        case .bluetoothUnavailable:
            return "Turn on Bluetooth in iOS Settings and grant Bluetooth permissions."
        case .wifiUnavailable:
            return "Connect to the same Wi-Fi network as the companion PC."
        case .unknown:
            return "Please restart the companion connection."
        }
    }
}

// MARK: - Connection Metrics

/// Diagnostic telemetry captured across the lifecycle of an active communication channel.
public struct ConnectionMetrics: Equatable, Sendable {
    /// Measured round-trip ping time in milliseconds.
    public var rttMilliseconds: Double

    /// Cumulative packets transmitted.
    public var packetsSent: UInt64

    /// Cumulative packets received from host.
    public var packetsReceived: UInt64

    /// Cumulative packets detected as dropped or lost.
    public var packetsLost: UInt64

    /// Total bytes written to the transport layer.
    public var bytesSent: UInt64

    /// Total bytes read from the transport layer.
    public var bytesReceived: UInt64

    /// Instantaneous packet throughput per second (Hz).
    public var packetRatePerSecond: Double

    /// Signal strength indicator (e.g. RSSI in dBm for Bluetooth).
    public var signalStrength: Int?

    /// Timestamp of this metrics snapshot.
    public var timestamp: Date

    public init(
        rttMilliseconds: Double = 0.0,
        packetsSent: UInt64 = 0,
        packetsReceived: UInt64 = 0,
        packetsLost: UInt64 = 0,
        bytesSent: UInt64 = 0,
        bytesReceived: UInt64 = 0,
        packetRatePerSecond: Double = 0.0,
        signalStrength: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.rttMilliseconds = rttMilliseconds
        self.packetsSent = packetsSent
        self.packetsReceived = packetsReceived
        self.packetsLost = packetsLost
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.packetRatePerSecond = packetRatePerSecond
        self.signalStrength = signalStrength
        self.timestamp = timestamp
    }
}

// MARK: - Communication Delegate

/// Delegate interface receiving asynchronous connection state transitions, inbound data,
/// performance metrics, and error notifications.
public protocol CommunicationDelegate: AnyObject {
    /// Informs the delegate that the communication channel has established a live connection.
    func didConnect(to channel: CommunicationChannel)

    /// Informs the delegate that the communication channel disconnected.
    ///
    /// - Parameters:
    ///   - channel: The communication channel that disconnected.
    ///   - error: The underlying error if abnormal disconnect, or `nil` if deliberate.
    func didDisconnect(from channel: CommunicationChannel, error: ConnectionError?)

    /// Informs the delegate that raw packet data was received from the host.
    ///
    /// - Parameters:
    ///   - data: Inbound binary packet data.
    ///   - channel: The channel receiving the data.
    func didReceiveData(_ data: Data, from channel: CommunicationChannel)

    /// Informs the delegate that updated telemetry/metrics are available.
    ///
    /// - Parameters:
    ///   - metrics: The latest diagnostic metrics snapshot.
    ///   - channel: The channel reporting metrics.
    func didUpdateMetrics(_ metrics: ConnectionMetrics, from channel: CommunicationChannel)

    /// Informs the delegate that an error occurred on the channel.
    ///
    /// - Parameters:
    ///   - error: The encountered connection error.
    ///   - channel: The channel encountering the error.
    func didEncounterError(_ error: ConnectionError, from channel: CommunicationChannel)
}

// MARK: - Default Delegate Implementations

public extension CommunicationDelegate {
    func didConnect(to channel: CommunicationChannel) {}
    func didDisconnect(from channel: CommunicationChannel, error: ConnectionError?) {}
    func didReceiveData(_ data: Data, from channel: CommunicationChannel) {}
    func didUpdateMetrics(_ metrics: ConnectionMetrics, from channel: CommunicationChannel) {}
    func didEncounterError(_ error: ConnectionError, from channel: CommunicationChannel) {}
}

// MARK: - Communication Channel Protocol

/// Abstract transport channel representing an ongoing or pending bidirectional connection
/// (e.g. CoreBluetooth Peripheral / L2CAP / GATT or UDP / TCP socket).
public protocol CommunicationChannel: AnyObject {
    /// Whether the channel currently has an established, writable connection.
    var isConnected: Bool { get }

    /// The physical/network transport type utilized by this channel.
    var connectionType: ConnectionType { get }

    /// Delegate receiving asynchronous transport lifecycle and data events.
    var delegate: CommunicationDelegate? { get set }

    /// Initiates connection establishment to the target companion host.
    func connect()

    /// Gracefully closes and tears down the active connection.
    func disconnect()

    /// Transmits raw binary packet data across the transport.
    ///
    /// - Parameter data: Binary packet data to write.
    func send(_ data: Data)
}

// MARK: - Communication Channel Convenience Extensions

public extension CommunicationChannel {

    /// Encodes and sends the latest controller state snapshot.
    ///
    /// - Parameter state: The controller state to send.
    func send(_ state: ControllerState) {
        let packet = PacketEncoder.encode(state)
        send(packet)
    }

    /// Encodes and sends a periodic heartbeat ping.
    func sendHeartbeat() {
        let packet = PacketEncoder.encodeHeartbeat()
        send(packet)
    }

    /// Encodes and sends a client handshake packet.
    ///
    /// - Parameter deviceName: Name of the current iOS device.
    func sendHandshake(deviceName: String) {
        let packet = PacketEncoder.encodeHandshake(deviceName: deviceName)
        send(packet)
    }

    /// Encodes and sends a graceful disconnect notification.
    func sendDisconnect() {
        let packet = PacketEncoder.encodeDisconnect()
        send(packet)
    }

    /// Encodes and sends a sequence acknowledgment.
    ///
    /// - Parameter sequence: Sequence identifier.
    func sendAck(sequence: UInt16) {
        let packet = PacketEncoder.encodeAck(sequence: sequence)
        send(packet)
    }
}
