//
//  Constants.swift
//  VNTM Gamepad
//
//  Central place for every tunable constant in the app.
//

import Foundation
import CoreGraphics
import CoreBluetooth

enum AppConstants {
    static let appName = "VNTM Gamepad"
    static let bundleId = "com.vntm.gamepad"
    static let appVersion = "1.0.0"

    // Backward compatibility aliases for existing codebase
    static var bundleIdentifier: String { bundleId }
    static var version: String { appVersion }
    static var build: String { "1" }
    static let supportURL = URL(string: "https://vntm.app/gamepad/support")!
    static let privacyPolicyURL = URL(string: "https://vntm.app/gamepad/privacy")!
    static let companionNameHints = ["VNTM", "Gamepad", "Companion"]

    enum BLE {
        static let serviceUUID = "VNTM-GP00-0001-0000-000000000000"
        static let characteristicUUID = "VNTM-GP00-0001-0000-000000000001"
        static let scanTimeout: TimeInterval = 10.0
    }

    enum WiFi {
        static let defaultPort: UInt16 = 7777
        static let serviceType = "_vntmgamepad._tcp"
        static let serviceDomain = "local."
    }

    enum Protocol {
        static let headerMagic: [UInt8] = [0x56, 0x4E]  // "VN"
        static let heartbeatInterval: TimeInterval = 0.1
        static let stateUpdateInterval: TimeInterval = 1.0 / 60.0  // 60Hz
        static let connectionTimeout: TimeInterval = 10.0
        static let maxRetries = 5
        static let reconnectBaseDelay: TimeInterval = 1.0
        static let maxReconnectDelay: TimeInterval = 30.0
    }

    enum Controller {
        static let stickCenter: UInt8 = 128
        static let stickMin: UInt8 = 0
        static let stickMax: UInt8 = 255
        static let triggerMin: UInt8 = 0
        static let triggerMax: UInt8 = 255
        static let defaultDeadZone: CGFloat = 0.15
        static let maxDeadZone: CGFloat = 0.5
        static let defaultSensitivity: Double = 1.0
    }

    enum UI {
        static let defaultOverlayOpacity: Double = 0.8
        static let minOverlayOpacity: Double = 0.3
        static let maxOverlayOpacity: Double = 1.0
        static let buttonDefaultSize: CGFloat = 60.0
        static let stickDefaultSize: CGFloat = 150.0
        static let animationDuration: Double = 0.15
    }

    enum UserDefaultsKeys {
        static let lastConnectedDevice = "lastConnectedDevice"
        static let preferredConnectionType = "preferredConnectionType"
        static let activeProfileId = "activeProfileId"
        static let savedProfiles = "savedProfiles"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hapticIntensity = "hapticIntensity"
        static let hapticEnabled = "hapticEnabled"
        static let motionEnabled = "motionEnabled"
    }
}

/// Timing budgets. Kept in one place so latency can be reasoned about.
enum Timing {
    /// Coalescing window for input packets. Touch changes are batched for at
    /// most this long before being written to the transport.
    static let inputFlushInterval: TimeInterval = 0.008

    /// Heartbeat / ping cadence required by the companion protocol.
    static let heartbeatInterval: TimeInterval = AppConstants.Protocol.heartbeatInterval

    /// How often the packet rate and byte counters are published to the UI.
    static let metricsInterval: TimeInterval = 0.25

    /// RSSI polling for Bluetooth.
    static let rssiPollInterval: TimeInterval = 2.0

    /// Socket keep-alive.
    static let wifiKeepAliveInterval: TimeInterval = 1.0

    /// A connection that has not acknowledged a packet for this long is
    /// considered unhealthy.
    static let connectionHealthTimeout: TimeInterval = AppConstants.Protocol.connectionTimeout

    /// Scan timeout before the UI stops the spinner.
    static let scanTimeout: TimeInterval = AppConstants.BLE.scanTimeout

    /// Motion is throttled to this rate. 60 Hz is plenty for look input.
    static let motionRate: Double = 60.0

    /// Reconnect backoff.
    static let reconnectBaseDelay: TimeInterval = AppConstants.Protocol.reconnectBaseDelay
    static let reconnectMaxDelay: TimeInterval = AppConstants.Protocol.maxReconnectDelay
    static let reconnectMaxAttempts: Int = AppConstants.Protocol.maxRetries
}

enum PacketConstants {
    /// "VN"
    static let magic0: UInt8 = AppConstants.Protocol.headerMagic[0]
    static let magic1: UInt8 = AppConstants.Protocol.headerMagic[1]
    static let version: UInt8 = 0x01

    static let headerLength = 10
    static let checksumLength = 2

    /// buttons(4) + sticks(4) + triggers(2) + timestamp(8)
    static let statePayloadLength = 18

    static let maxPayloadLength = 1_024
    static let maxPacketLength = 4_096

    static let flagEncrypted: UInt8 = 0x01

    /// AES-GCM overhead: 12-byte nonce + 16-byte tag.
    static let gcmOverhead = 28
}

enum BLEConstants {
    /// Primary service advertised by the companion.
    static let service = CBUUID(string: AppConstants.BLE.serviceUUID)

    /// Client -> companion. Controller state and pings are written here.
    static let stateCharacteristic = CBUUID(string: AppConstants.BLE.characteristicUUID)

    /// Companion -> client. Acknowledgements and RTT echoes.
    static let ackCharacteristic = CBUUID(string: "VNTM-GP00-0001-0000-000000000002")

    static let restoreIdentifier = "\(AppConstants.bundleId).central"

    /// iOS will not sustain a 120 Hz write stream without flow control, so
    /// packets are dropped (newest wins) when the peripheral is not ready.
    static let maximumPendingWrites = 1
}

enum WiFiConstants {
    static let bonjourServiceType = AppConstants.WiFi.serviceType
    static let defaultPort: UInt16 = AppConstants.WiFi.defaultPort
    static let defaultHost = "192.168.1.100"
}

enum StorageKey {
    static let settings = "vntm.settings.v1"
    static let profiles = AppConstants.UserDefaultsKeys.savedProfiles
    static let activeProfileID = AppConstants.UserDefaultsKeys.activeProfileId
    static let lastConnection = AppConstants.UserDefaultsKeys.lastConnectedDevice
    static let onboardingCompleted = AppConstants.UserDefaultsKeys.hasCompletedOnboarding
    static let encryptionPassphrase = "vntm.crypto.passphrase"
}

enum UIConstants {
    static let controllerPadding: CGFloat = 18
    static let buttonCornerRadius: CGFloat = 18
    static let panelCornerRadius: CGFloat = 22
    static let animationDuration: Double = AppConstants.UI.animationDuration
    static let buttonDefaultSize: CGFloat = AppConstants.UI.buttonDefaultSize
    static let stickDefaultSize: CGFloat = AppConstants.UI.stickDefaultSize
}
