//
//  ControllerState.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//

import Foundation

/// Digital button masks corresponding to standard controller button bits.
public enum ButtonMask: UInt32, Codable, CaseIterable, Sendable {
    case a = 1
    case b = 2
    case x = 4
    case y = 8
    case lb = 16
    case rb = 32
    case start = 64
    case select = 128
    case home = 256
    case leftStick = 512
    case rightStick = 1024

    // MARK: - UpperCamelCase Aliases
    public static let A = ButtonMask.a
    public static let B = ButtonMask.b
    public static let X = ButtonMask.x
    public static let Y = ButtonMask.y
    public static let LB = ButtonMask.lb
    public static let RB = ButtonMask.rb
    public static let Start = ButtonMask.start
    public static let Select = ButtonMask.select
    public static let Home = ButtonMask.home
    public static let LeftStick = ButtonMask.leftStick
    public static let RightStick = ButtonMask.rightStick

    /// Human-readable display label.
    public var displayName: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .lb: return "LB"
        case .rb: return "RB"
        case .start: return "Start"
        case .select: return "Select"
        case .home: return "Home"
        case .leftStick: return "LS"
        case .rightStick: return "RS"
        }
    }
}

/// D-Pad directional state covering all 8 compass headings and center idle.
public enum DPadDirection: String, Codable, CaseIterable, Sendable {
    case up
    case upRight
    case right
    case downRight
    case down
    case downLeft
    case left
    case upLeft
    case center

    /// Numeric byte index for high-performance wire serialization.
    public var byteValue: UInt8 {
        switch self {
        case .center: return 0
        case .up: return 1
        case .upRight: return 2
        case .right: return 3
        case .downRight: return 4
        case .down: return 5
        case .downLeft: return 6
        case .left: return 7
        case .upLeft: return 8
        }
    }

    /// Initializes a directional state from its binary wire representation.
    public init(byteValue: UInt8) {
        switch byteValue {
        case 1: self = .up
        case 2: self = .upRight
        case 3: self = .right
        case 4: self = .downRight
        case 5: self = .down
        case 6: self = .downLeft
        case 7: self = .left
        case 8: self = .upLeft
        default: self = .center
        }
    }

    /// Neutral / centered alias.
    public static let none: DPadDirection = .center
}

/// 6-axis motion snapshot capturing gyroscopic orientation and linear acceleration.
public struct MotionData: Codable, Equatable, Sendable {
    /// Pitch angle in degrees/radians.
    public var pitch: Double
    /// Roll angle in degrees/radians.
    public var roll: Double
    /// Yaw angle in degrees/radians.
    public var yaw: Double
    /// X-axis linear acceleration in Gs.
    public var accelerationX: Double
    /// Y-axis linear acceleration in Gs.
    public var accelerationY: Double
    /// Z-axis linear acceleration in Gs.
    public var accelerationZ: Double

    public init(
        pitch: Double = 0.0,
        roll: Double = 0.0,
        yaw: Double = 0.0,
        accelerationX: Double = 0.0,
        accelerationY: Double = 0.0,
        accelerationZ: Double = 0.0
    ) {
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.accelerationX = accelerationX
        self.accelerationY = accelerationY
        self.accelerationZ = accelerationZ
    }
}

/// The core controller state struct representing the entire instantaneous state of the gamepad.
public struct ControllerState: Codable, Equatable, Sendable {
    /// Bitmask for digital buttons.
    public var buttons: UInt32

    /// Left stick X-axis (0-255, 128 is center).
    public var leftStickX: UInt8

    /// Left stick Y-axis (0-255, 128 is center).
    public var leftStickY: UInt8

    /// Right stick X-axis (0-255, 128 is center).
    public var rightStickX: UInt8

    /// Right stick Y-axis (0-255, 128 is center).
    public var rightStickY: UInt8

    /// Left analog trigger squeeze (0-255).
    public var leftTrigger: UInt8

    /// Right analog trigger squeeze (0-255).
    public var rightTrigger: UInt8

    /// Current direction of the directional pad.
    public var dpadState: DPadDirection

    /// Optional 6-axis motion tracking data.
    public var motionData: MotionData?

    /// Monotonic timestamp in milliseconds.
    public var timestamp: UInt64

    /// Center resting value for analog sticks.
    public static let stickCenter: UInt8 = 128

    /// Default initializer setting sticks to 128 (center), triggers to 0, and buttons to 0.
    public init(
        buttons: UInt32 = 0,
        leftStickX: UInt8 = ControllerState.stickCenter,
        leftStickY: UInt8 = ControllerState.stickCenter,
        rightStickX: UInt8 = ControllerState.stickCenter,
        rightStickY: UInt8 = ControllerState.stickCenter,
        leftTrigger: UInt8 = 0,
        rightTrigger: UInt8 = 0,
        dpadState: DPadDirection = .center,
        motionData: MotionData? = nil,
        timestamp: UInt64 = Date.monotonicMilliseconds
    ) {
        self.buttons = buttons
        self.leftStickX = leftStickX
        self.leftStickY = leftStickY
        self.rightStickX = rightStickX
        self.rightStickY = rightStickY
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.dpadState = dpadState
        self.motionData = motionData
        self.timestamp = timestamp
    }

    // MARK: - Helper Methods

    /// Checks if a specific button is currently active in the bitmask.
    public func isButtonPressed(_ button: ButtonMask) -> Bool {
        (buttons & button.rawValue) != 0
    }

    /// Sets the specified button's bit to active in the bitmask.
    public mutating func pressButton(_ button: ButtonMask) {
        buttons |= button.rawValue
    }

    /// Clears the specified button's bit in the bitmask.
    public mutating func releaseButton(_ button: ButtonMask) {
        buttons &= ~button.rawValue
    }

    /// Updates the state of the specified button in the bitmask.
    public mutating func setButtonPressed(_ button: ButtonMask, isPressed: Bool) {
        if isPressed {
            pressButton(button)
        } else {
            releaseButton(button)
        }
    }

    /// Resets all controls to their neutral resting state.
    public mutating func resetToNeutral() {
        buttons = 0
        leftStickX = ControllerState.stickCenter
        leftStickY = ControllerState.stickCenter
        rightStickX = ControllerState.stickCenter
        rightStickY = ControllerState.stickCenter
        leftTrigger = 0
        rightTrigger = 0
        dpadState = .center
        motionData = nil
    }

    /// Returns a new neutral controller state.
    public static func neutral() -> ControllerState {
        ControllerState()
    }

    // MARK: - Wire Binary Serialization

    /// Serializes the controller state into a compact binary wire payload
    /// (19 bytes: 4 buttons + 2 leftStick + 2 rightStick + 2 triggers + 1 dpad + 8 timestamp, skipping motion for low latency).
    public func toData() -> Data {
        var data = Data(capacity: 19)
        var btnBig = buttons.bigEndian
        withUnsafeBytes(of: &btnBig) { data.append(contentsOf: $0) }
        data.append(leftStickX)
        data.append(leftStickY)
        data.append(rightStickX)
        data.append(rightStickY)
        data.append(leftTrigger)
        data.append(rightTrigger)
        data.append(dpadState.byteValue)
        var tsBig = timestamp.bigEndian
        withUnsafeBytes(of: &tsBig) { data.append(contentsOf: $0) }
        return data
    }

    /// Deserializes a controller state from a compact binary payload.
    public init?(data: Data) {
        guard data.count >= 19 else { return nil }
        let bytes = [UInt8](data)
        self.buttons = UInt32(bigEndianBytes: bytes, offset: 0)
        self.leftStickX = bytes[4]
        self.leftStickY = bytes[5]
        self.rightStickX = bytes[6]
        self.rightStickY = bytes[7]
        self.leftTrigger = bytes[8]
        self.rightTrigger = bytes[9]
        self.dpadState = DPadDirection(byteValue: bytes[10])
        self.timestamp = UInt64(bigEndianBytes: bytes, offset: 11)
        self.motionData = nil
    }

    /// Wire format payload accessor for transport backward compatibility.
    public var payload: Data {
        toData()
    }
}

// MARK: - Backward Compatibility Support for Legacy Resolvers

/// Controller button identifiers supported by layout and gesture resolvers.
public enum ControllerButton: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case a, b, x, y
    case lb, rb
    case start, select, home
    case dpadUp, dpadDown, dpadLeft, dpadRight

    public var id: String { rawValue }

    public var mask: ButtonMask? {
        switch self {
        case .a: return .a
        case .b: return .b
        case .x: return .x
        case .y: return .y
        case .lb: return .lb
        case .rb: return .rb
        case .start: return .start
        case .select: return .select
        case .home: return .home
        default: return nil
        }
    }
}

// MARK: - Legacy Compatibility Extension

extension ControllerState {
    public var dpadDirection: DPadDirection {
        get { dpadState }
        set { dpadState = newValue }
    }

    public mutating func setDPad(_ direction: DPadDirection) {
        dpadState = direction
    }

    public func isPressed(_ button: ControllerButton) -> Bool {
        if let mask = button.mask {
            return isButtonPressed(mask)
        }
        switch button {
        case .dpadUp:
            return dpadState == .up || dpadState == .upRight || dpadState == .upLeft
        case .dpadDown:
            return dpadState == .down || dpadState == .downRight || dpadState == .downLeft
        case .dpadLeft:
            return dpadState == .left || dpadState == .downLeft || dpadState == .upLeft
        case .dpadRight:
            return dpadState == .right || dpadState == .downRight || dpadState == .upRight
        default:
            return false
        }
    }
}
