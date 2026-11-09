//
//  ControllerProfile.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//

import Foundation
import CoreGraphics

// MARK: - Layout Type

/// Visual and functional layout configurations supported by the gamepad.
public enum LayoutType: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Classic Xbox-style layout with dual analog thumbsticks, triggers, and face buttons.
    case classic
    /// Arcade layout with prominent 8-way directional pad and clustered action buttons.
    case arcade
    /// Racing layout featuring a central steering wheel, analog pedals, and gear paddles.
    case racing
    /// Fully customizable layout allowing users to freely drag, scale, and place controls.
    case custom

    public var id: String { rawValue }

    /// User-facing display title for layout pickers.
    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .arcade: return "Arcade"
        case .racing: return "Racing"
        case .custom: return "Custom"
        }
    }

    /// Descriptive summary of the layout's primary control configuration.
    public var subtitle: String {
        switch self {
        case .classic: return "Dual sticks, Xbox-style layout"
        case .arcade: return "D-Pad and action buttons"
        case .racing: return "Steering wheel and analog pedals"
        case .custom: return "User-defined custom placement"
        }
    }

    /// SF Symbol icon representation for navigation and settings.
    public var symbolName: String {
        switch self {
        case .classic: return "gamecontroller.fill"
        case .arcade: return "arcade.stick"
        case .racing: return "steeringwheel"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// MARK: - Sensitivity Settings

/// Sensitivity multipliers applied to analog sticks, triggers, and gyroscopic motion sensors.
public struct SensitivitySettings: Codable, Equatable, Sendable {
    /// Left analog stick multiplier (supported range: 0.1 to 3.0, default: 1.0).
    public var leftStickSensitivity: Double

    /// Right analog stick multiplier (supported range: 0.1 to 3.0, default: 1.0).
    public var rightStickSensitivity: Double

    /// Left analog trigger sensitivity (supported range: 0.1 to 3.0, default: 1.0).
    public var leftTriggerSensitivity: Double

    /// Right analog trigger sensitivity (supported range: 0.1 to 3.0, default: 1.0).
    public var rightTriggerSensitivity: Double

    /// Gyroscope and motion panning sensitivity (supported range: 0.1 to 3.0, default: 1.0).
    public var motionSensitivity: Double

    /// Default baseline sensitivity settings.
    public static var `default`: SensitivitySettings {
        SensitivitySettings(
            leftStickSensitivity: 1.0,
            rightStickSensitivity: 1.0,
            leftTriggerSensitivity: 1.0,
            rightTriggerSensitivity: 1.0,
            motionSensitivity: 1.0
        )
    }

    public init(
        leftStickSensitivity: Double = 1.0,
        rightStickSensitivity: Double = 1.0,
        leftTriggerSensitivity: Double = 1.0,
        rightTriggerSensitivity: Double = 1.0,
        motionSensitivity: Double = 1.0
    ) {
        self.leftStickSensitivity = min(max(leftStickSensitivity, 0.1), 3.0)
        self.rightStickSensitivity = min(max(rightStickSensitivity, 0.1), 3.0)
        self.leftTriggerSensitivity = min(max(leftTriggerSensitivity, 0.1), 3.0)
        self.rightTriggerSensitivity = min(max(rightTriggerSensitivity, 0.1), 3.0)
        self.motionSensitivity = min(max(motionSensitivity, 0.1), 3.0)
    }
}

// MARK: - Dead Zone Settings

/// Dead zone thresholds preventing unwanted analog stick drift and unintentional trigger engagement.
public struct DeadZoneSettings: Codable, Equatable, Sendable {
    /// Inner dead zone threshold for left thumbstick (0.0 to 0.5, default: 0.08).
    public var leftStickDeadZone: Double

    /// Inner dead zone threshold for right thumbstick (0.0 to 0.5, default: 0.08).
    public var rightStickDeadZone: Double

    /// Initial dead travel threshold for left trigger (0.0 to 0.5, default: 0.05).
    public var leftTriggerDeadZone: Double

    /// Initial dead travel threshold for right trigger (0.0 to 0.5, default: 0.05).
    public var rightTriggerDeadZone: Double

    /// Default factory dead zone thresholds.
    public static var `default`: DeadZoneSettings {
        DeadZoneSettings(
            leftStickDeadZone: 0.08,
            rightStickDeadZone: 0.08,
            leftTriggerDeadZone: 0.05,
            rightTriggerDeadZone: 0.05
        )
    }

    public init(
        leftStickDeadZone: Double = 0.08,
        rightStickDeadZone: Double = 0.08,
        leftTriggerDeadZone: Double = 0.05,
        rightTriggerDeadZone: Double = 0.05
    ) {
        self.leftStickDeadZone = Self.clamp(leftStickDeadZone)
        self.rightStickDeadZone = Self.clamp(rightStickDeadZone)
        self.leftTriggerDeadZone = Self.clamp(leftTriggerDeadZone)
        self.rightTriggerDeadZone = Self.clamp(rightTriggerDeadZone)
    }

    /// Clamps a dead zone value to the valid range (0.0 ... 0.5).
    public static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 0.5)
    }
}

// MARK: - Button Position & Custom Layout

/// Screen coordinate placement and sizing for an individual on-screen gamepad control.
public struct ButtonPosition: Codable, Equatable, Sendable {
    /// Horizontal coordinate position (normalized or canvas-relative points).
    public var x: CGFloat

    /// Vertical coordinate position (normalized or canvas-relative points).
    public var y: CGFloat

    /// Diameter or dimension in screen points.
    public var size: CGFloat

    public init(x: CGFloat, y: CGFloat, size: CGFloat = 60.0) {
        self.x = x
        self.y = y
        self.size = size
    }
}

/// Custom layout mapping control identifiers to screen coordinates and sizes.
public struct CustomLayout: Codable, Equatable, Sendable {
    /// Dictionary of button position mappings keyed by control identifier strings.
    public var buttonPositions: [String: ButtonPosition]

    public init(buttonPositions: [String: ButtonPosition] = [:]) {
        self.buttonPositions = buttonPositions
    }

    public subscript(key: String) -> ButtonPosition? {
        get { buttonPositions[key] }
        set { buttonPositions[key] = newValue }
    }
}

// MARK: - Theme Type

/// Visual skin and color palette themes for on-screen controls and overlays.
public enum ThemeType: String, Codable, CaseIterable, Identifiable, Sendable {
    /// High-contrast bright theme.
    case light
    /// Clean dark theme optimized for standard low-light gaming.
    case dark
    /// Vibrant neon aesthetic with cyber glow accents.
    case neon
    /// Pure black OLED midnight theme for minimum battery drain.
    case midnight
    /// User-customized palette.
    case custom

    public var id: String { rawValue }

    /// Human-friendly name of the theme.
    public var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .neon: return "Neon Cyber"
        case .midnight: return "Midnight OLED"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Response Curves (Input Shaping)

/// Response curve equations translating normalized deflections into input values.
public enum ResponseCurve: String, Codable, CaseIterable, Identifiable, Sendable {
    case linear
    case quadratic
    case exponential
    case sigmoid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .quadratic: return "Precision"
        case .exponential: return "Aggressive"
        case .sigmoid: return "S-Curve"
        }
    }

    /// Evaluates the response curve mapping an input in 0...1 to an output in 0...1.
    public func apply(_ value: Double) -> Double {
        let x = min(max(value, 0.0), 1.0)
        switch self {
        case .linear:
            return x
        case .quadratic:
            return x * x
        case .exponential:
            let k = 3.0
            return (exp(k * x) - 1.0) / (exp(k) - 1.0)
        case .sigmoid:
            return x * x * (3.0 - 2.0 * x)
        }
    }
}

// MARK: - Controller Profile

/// Complete profile containing layout choices, button remappings, sensitivity, dead zones, and styling.
public struct ControllerProfile: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for the profile.
    public var id: UUID

    /// Friendly user-assigned profile name.
    public var name: String

    /// Selected visual layout preset.
    public var layout: LayoutType

    /// Button remapping lookup table (source button name -> target button name).
    public var buttonMapping: [String: String]

    /// Analog stick and trigger sensitivity calibration.
    public var sensitivity: SensitivitySettings

    /// Analog stick and trigger dead zone thresholds.
    public var deadZones: DeadZoneSettings

    /// Optional custom button placements when using LayoutType.custom.
    public var customLayout: CustomLayout?

    /// Haptic feedback vibration intensity from 0.0 (off) to 1.0 (full strength).
    public var hapticIntensity: Double

    /// Visual opacity for touch controls and overlay HUD from 0.3 to 1.0.
    public var overlayOpacity: Double

    /// Visual appearance theme.
    public var theme: ThemeType

    /// System default controller profile.
    public static var `default`: ControllerProfile {
        ControllerProfile(
            id: UUID(),
            name: "Default Profile",
            layout: .classic,
            buttonMapping: [:],
            sensitivity: .default,
            deadZones: .default,
            customLayout: nil,
            hapticIntensity: 1.0,
            overlayOpacity: 0.8,
            theme: .dark
        )
    }

    public init(
        id: UUID = UUID(),
        name: String = "Default Profile",
        layout: LayoutType = .classic,
        buttonMapping: [String: String] = [:],
        sensitivity: SensitivitySettings = .default,
        deadZones: DeadZoneSettings = .default,
        customLayout: CustomLayout? = nil,
        hapticIntensity: Double = 1.0,
        overlayOpacity: Double = 0.8,
        theme: ThemeType = .dark
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.buttonMapping = buttonMapping
        self.sensitivity = sensitivity
        self.deadZones = deadZones
        self.customLayout = customLayout
        self.hapticIntensity = min(max(hapticIntensity, 0.0), 1.0)
        self.overlayOpacity = min(max(overlayOpacity, 0.3), 1.0)
        self.theme = theme
    }

    // MARK: - Preset Factory Constructors

    /// Creates a classic Xbox-style controller profile.
    public static func classic() -> ControllerProfile {
        ControllerProfile(
            name: "Classic",
            layout: .classic,
            theme: .dark
        )
    }

    /// Creates an arcade-style layout profile.
    public static func arcade() -> ControllerProfile {
        ControllerProfile(
            name: "Arcade",
            layout: .arcade,
            theme: .neon
        )
    }

    /// Creates a racing simulation layout profile.
    public static func racing() -> ControllerProfile {
        ControllerProfile(
            name: "Racing",
            layout: .racing,
            theme: .midnight
        )
    }
}
