//
//  GameControllerViewModel.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//  MVVM Architecture with Combine Framework
//

import Foundation
import SwiftUI
import Combine
import CoreGraphics
import os.log

/// Primary ViewModel responsible for aggregating real-time player inputs,
/// applying profile transformations (sensitivity curves, dead zones, button remappings),
/// tracking connection state, and dispatching wire packets at ~60Hz with background heartbeats.
@MainActor
public final class GameControllerViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Real-time snapshot of digital buttons, thumbsticks, analog triggers, d-pad, and motion telemetry.
    @Published public var controllerState: ControllerState

    /// Whether there is an active wireless connection (Bluetooth LE or Wi-Fi TCP) ready for streaming.
    @Published public var isConnected: Bool = false

    /// Active on-screen layout configuration (classic Xbox, arcade, racing, or custom).
    @Published public var activeLayout: LayoutType = .classic

    /// Current round-trip transmission latency in milliseconds.
    @Published public var latency: Double = 0.0

    /// Controls visibility of the hardware test and calibration modal sheet.
    @Published public var showCalibration: Bool = false

    /// Whether real-time gyroscopic motion controls are actively streaming sensor input.
    @Published public var isMotionActive: Bool = false

    // MARK: - Injected Dependencies

    private let bluetoothService: BluetoothService
    private let wiFiService: WiFiService
    private let hapticService: HapticService
    private let motionService: MotionService
    private let profileService: ProfileService

    // MARK: - Timers & Schedulers

    /// High-frequency timer dispatching controller state updates at ~60Hz (~16.6ms).
    private var stateSendTimer: AnyCancellable?

    /// Periodic heartbeat ping timer executing every 100ms (10Hz).
    private var heartbeatTimer: AnyCancellable?

    /// Retained Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Native unified system logger.
    private let logger = Logger(subsystem: "com.vntm.gamepad", category: "GameControllerViewModel")

    // MARK: - Initialization

    /// Initializes a new instance of GameControllerViewModel with injected services.
    ///
    /// - Parameters:
    ///   - bluetoothService: Low-energy Bluetooth communication transport.
    ///   - wiFiService: High-throughput local Wi-Fi TCP network transport.
    ///   - hapticService: Tactile feedback engine for button clicks and trigger resistance.
    ///   - motionService: Gyroscopic 6-axis device attitude and acceleration sensor pipeline.
    ///   - profileService: Storage and configuration manager for layouts, sensitivities, and dead zones.
    public init(
        bluetoothService: BluetoothService,
        wiFiService: WiFiService,
        hapticService: HapticService,
        motionService: MotionService,
        profileService: ProfileService
    ) {
        self.bluetoothService = bluetoothService
        self.wiFiService = wiFiService
        self.hapticService = hapticService
        self.motionService = motionService
        self.profileService = profileService

        // Initialize state to neutral defaults
        self.controllerState = ControllerState.neutral()
        self.activeLayout = profileService.activeProfile.layout

        setupSubscriptions()
        logger.info("GameControllerViewModel initialized. Layout: \(self.activeLayout.displayName)")
    }

    deinit {
        stateSendTimer?.cancel()
        heartbeatTimer?.cancel()
    }

    // MARK: - Combine Setup

    /// Subscribes to dependency service publishers to synchronize connection, profile, and motion state.
    private func setupSubscriptions() {
        // 1. Observe Active Controller Profile changes (Layout, Sensitivities, Deadzones)
        profileService.$activeProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                guard let self = self else { return }
                self.activeLayout = profile.layout
                self.logger.debug("Active profile updated: \(profile.name), layout: \(profile.layout.rawValue)")
            }
            .store(in: &cancellables)

        // 2. Observe Bluetooth and Wi-Fi connection states to drive unified `isConnected`
        Publishers.CombineLatest(bluetoothService.$connectionStatus, wiFiService.$connectionStatus)
            .map { btStatus, wifiStatus in
                btStatus == .connected || wifiStatus == .connected
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self = self else { return }
                let previous = self.isConnected
                self.isConnected = connected

                if connected && !previous {
                    self.logger.info("Active connection established. Starting 60Hz state stream and 100ms heartbeat.")
                    self.startHeartbeat()
                    self.startStateStreaming()
                    self.hapticService.playConnectionEvent(connected: true)
                } else if !connected && previous {
                    self.logger.info("Connection lost. Stopping state stream and resetting inputs to neutral.")
                    self.stopStateStreaming()
                    self.stopHeartbeat()
                    self.controllerState.resetToNeutral()
                    self.latency = 0.0
                    self.hapticService.playConnectionEvent(connected: false)
                }
            }
            .store(in: &cancellables)

        // 3. Observe Wi-Fi latency benchmarks
        wiFiService.$latency
            .filter { $0 > 0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ping in
                guard let self = self else { return }
                if self.wiFiService.connectionStatus == .connected {
                    self.latency = ping
                }
            }
            .store(in: &cancellables)

        // 4. Observe Motion Service sensor attitude updates and merge into ControllerState
        Publishers.CombineLatest(motionService.$pitch, motionService.$roll)
            .combineLatest(motionService.$yaw, motionService.$isActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] attitude, yaw, isActive in
                guard let self = self else { return }
                self.isMotionActive = isActive
                if isActive {
                    let (pitch, roll) = attitude
                    self.controllerState.motionData = MotionData(
                        pitch: pitch,
                        roll: roll,
                        yaw: yaw,
                        accelerationX: self.motionService.accelerationX,
                        accelerationY: self.motionService.accelerationY,
                        accelerationZ: self.motionService.accelerationZ
                    )
                } else {
                    self.controllerState.motionData = nil
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Input Processing Methods

    /// Updates the state of a digital button, applying active profile remapping and tactile feedback.
    ///
    /// - Parameters:
    ///   - button: The physical button that was actuated.
    ///   - pressed: `true` if pressed down, `false` upon release.
    public func updateButton(_ button: ButtonMask, pressed: Bool) {
        let remappedButton = resolveRemappedButton(button)
        controllerState.setButtonPressed(remappedButton, isPressed: pressed)

        if pressed {
            hapticService.playButtonPress()
        }
    }

    /// Convenience overload updating digital button state from a `ControllerButton` enum.
    ///
    /// - Parameters:
    ///   - button: The controller button identifier.
    ///   - pressed: `true` if pressed down, `false` upon release.
    public func updateButton(_ button: ControllerButton, pressed: Bool) {
        if let mask = button.mask {
            updateButton(mask, pressed: pressed)
        }
    }

    /// Updates the left thumbstick position, normalizing from (-1.0...1.0) into (0...255)
    /// while applying radial dead zone filtering and nonlinear sensitivity curves.
    ///
    /// - Parameters:
    ///   - x: Horizontal deflection (-1.0 to 1.0, where 0.0 is center).
    ///   - y: Vertical deflection (-1.0 to 1.0, where 0.0 is center, up is positive).
    public func updateLeftStick(x: CGFloat, y: CGFloat) {
        let deadZone = profileService.activeProfile.deadZones.leftStickDeadZone
        let sensitivity = profileService.activeProfile.sensitivity.leftStickSensitivity

        let (byteX, byteY) = processAnalogStick(
            x: x,
            y: y,
            deadZone: deadZone,
            sensitivity: sensitivity
        )

        controllerState.leftStickX = byteX
        controllerState.leftStickY = byteY

        // Edge boundary tactile feedback
        let magnitude = hypot(Double(x), Double(y))
        if magnitude >= 0.98 {
            hapticService.playStickBoundary()
        }
    }

    /// Updates the right thumbstick position, normalizing from (-1.0...1.0) into (0...255)
    /// while applying radial dead zone filtering and nonlinear sensitivity curves.
    ///
    /// - Parameters:
    ///   - x: Horizontal deflection (-1.0 to 1.0, where 0.0 is center).
    ///   - y: Vertical deflection (-1.0 to 1.0, where 0.0 is center, up is positive).
    public func updateRightStick(x: CGFloat, y: CGFloat) {
        let deadZone = profileService.activeProfile.deadZones.rightStickDeadZone
        let sensitivity = profileService.activeProfile.sensitivity.rightStickSensitivity

        let (byteX, byteY) = processAnalogStick(
            x: x,
            y: y,
            deadZone: deadZone,
            sensitivity: sensitivity
        )

        controllerState.rightStickX = byteX
        controllerState.rightStickY = byteY

        // Edge boundary tactile feedback
        let magnitude = hypot(Double(x), Double(y))
        if magnitude >= 0.98 {
            hapticService.playStickBoundary()
        }
    }

    /// Updates the left analog trigger squeeze (LT), normalizing from (0.0...1.0) into (0...255)
    /// with dead zone trimming, response curve shaping, and pressure haptic feedback.
    ///
    /// - Parameter value: Normalized trigger pull travel (0.0 to 1.0).
    public func updateLeftTrigger(value: CGFloat) {
        let deadZone = profileService.activeProfile.deadZones.leftTriggerDeadZone
        let sensitivity = profileService.activeProfile.sensitivity.leftTriggerSensitivity

        let byteValue = processTrigger(value: value, deadZone: deadZone, sensitivity: sensitivity)
        controllerState.leftTrigger = byteValue

        // Dynamic resistance tactile feedback
        hapticService.playTriggerFeedback(pressure: Float(value))
    }

    /// Updates the right analog trigger squeeze (RT), normalizing from (0.0...1.0) into (0...255)
    /// with dead zone trimming, response curve shaping, and pressure haptic feedback.
    ///
    /// - Parameter value: Normalized trigger pull travel (0.0 to 1.0).
    public func updateRightTrigger(value: CGFloat) {
        let deadZone = profileService.activeProfile.deadZones.rightTriggerDeadZone
        let sensitivity = profileService.activeProfile.sensitivity.rightTriggerSensitivity

        let byteValue = processTrigger(value: value, deadZone: deadZone, sensitivity: sensitivity)
        controllerState.rightTrigger = byteValue

        // Dynamic resistance tactile feedback
        hapticService.playTriggerFeedback(pressure: Float(value))
    }

    /// Updates the directional pad state across all 8 headings or center resting state.
    ///
    /// - Parameter direction: The active compass heading or `.center`.
    public func updateDPad(direction: DPadDirection) {
        controllerState.dpadState = direction
        controllerState.setDPad(direction)

        if direction != .center {
            hapticService.playButtonPress()
        }
    }

    /// Toggles 6-axis device gyro motion controls on or off.
    public func toggleMotionControls() {
        if motionService.isActive {
            motionService.stopUpdates()
            controllerState.motionData = nil
            isMotionActive = false
            logger.info("Motion controls disabled.")
        } else {
            motionService.startUpdates(interval: 1.0 / 60.0)
            isMotionActive = true
            logger.info("Motion controls enabled at 60Hz.")
        }
    }

    // MARK: - State Transmission & Heartbeat

    /// Encodes the current controller state snapshot into binary wire format and dispatches
    /// it immediately over the active wireless transport (BLE or Wi-Fi).
    public func sendState() {
        guard isConnected else { return }

        // Refresh monotonic timestamp prior to framing
        controllerState.timestamp = Date.monotonicMilliseconds

        let packetData = PacketEncoder.encode(controllerState)

        if bluetoothService.connectionStatus == .connected {
            bluetoothService.send(packetData)
        } else if wiFiService.connectionStatus == .connected {
            wiFiService.send(packetData)
        }
    }

    /// Starts high-frequency streaming timer sending state packets at ~60Hz (~16.6ms).
    private func startStateStreaming() {
        stateSendTimer?.cancel()
        stateSendTimer = Timer.publish(every: 1.0 / 60.0, tolerance: 0.002, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendState()
            }
    }

    /// Stops high-frequency state streaming timer.
    private func stopStateStreaming() {
        stateSendTimer?.cancel()
        stateSendTimer = nil
    }

    /// Starts periodic heartbeat ping transmission running every 100ms.
    public func startHeartbeat() {
        stopHeartbeat()

        heartbeatTimer = Timer.publish(every: 0.1, tolerance: 0.01, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendHeartbeat()
            }
    }

    /// Stops periodic heartbeat timer.
    public func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    /// Sends a single framed heartbeat packet over the active connection.
    private func sendHeartbeat() {
        guard isConnected else { return }

        let heartbeatPacket = PacketEncoder.encodeHeartbeat(timestamp: Date.monotonicMilliseconds)

        if bluetoothService.connectionStatus == .connected {
            bluetoothService.send(heartbeatPacket)
        } else if wiFiService.connectionStatus == .connected {
            wiFiService.send(heartbeatPacket)
        }
    }

    // MARK: - Dead Zone & Sensitivity Calculations

    /// Shapes analog thumbstick deflection applying radial deadzone and power sensitivity curves.
    ///
    /// - Formula:
    ///   - If `magnitude < deadzone`: returns center `(128, 128)`.
    ///   - Rescaled: `normalizedMag = (magnitude - deadzone) / (1.0 - deadzone)`
    ///   - Curve: `curvedMag = pow(normalizedMag, 1.0 / sensitivity)`
    ///   - Maps `(-1...1)` to `(0...255)` with `0.0` deflection landing at `128`.
    private func processAnalogStick(
        x: CGFloat,
        y: CGFloat,
        deadZone: Double,
        sensitivity: Double
    ) -> (UInt8, UInt8) {
        let clampedX = Double(min(max(x, -1.0), 1.0))
        let clampedY = Double(min(max(y, -1.0), 1.0))

        let magnitude = hypot(clampedX, clampedY)
        let effectiveDeadZone = min(max(deadZone, 0.0), 0.5)

        // Dead zone filter: return center if below threshold
        guard magnitude > effectiveDeadZone else {
            return (ControllerState.stickCenter, ControllerState.stickCenter)
        }

        // Rescale remaining travel from deadzone boundary to unit circle
        let remainingRange = 1.0 - effectiveDeadZone
        guard remainingRange > 0.0001 else {
            return (ControllerState.stickCenter, ControllerState.stickCenter)
        }

        let normalizedMag = min(max((magnitude - effectiveDeadZone) / remainingRange, 0.0), 1.0)

        // Apply sensitivity curve: value = pow(normalizedValue, 1.0 / sensitivity)
        let safeSensitivity = max(sensitivity, 0.1)
        let curvedMag = pow(normalizedMag, 1.0 / safeSensitivity)

        // Calculate directional unit vector and apply curved magnitude
        let dirX = clampedX / magnitude
        let dirY = clampedY / magnitude
        let finalX = dirX * curvedMag
        let finalY = dirY * curvedMag

        // Map -1.0...1.0 onto 0...255 (where 0.0 maps to 128)
        let byteX = UInt8(min(max(((finalX + 1.0) / 2.0 * 255.0).rounded(), 0.0), 255.0))
        let byteY = UInt8(min(max(((finalY + 1.0) / 2.0 * 255.0).rounded(), 0.0), 255.0))

        return (byteX, byteY)
    }

    /// Shapes analog trigger squeeze applying initial dead travel and power sensitivity curves.
    ///
    /// - Formula:
    ///   - If `value < deadzone`: returns `0`.
    ///   - Rescaled: `normalized = (value - deadzone) / (1.0 - deadzone)`
    ///   - Curve: `curved = pow(normalized, 1.0 / sensitivity)`
    ///   - Maps `(0...1)` to `(0...255)`.
    private func processTrigger(
        value: CGFloat,
        deadZone: Double,
        sensitivity: Double
    ) -> UInt8 {
        let clampedVal = Double(min(max(value, 0.0), 1.0))
        let effectiveDeadZone = min(max(deadZone, 0.0), 0.5)

        // Dead zone filter: return zero squeeze if below threshold
        guard clampedVal > effectiveDeadZone else {
            return 0
        }

        let remainingRange = 1.0 - effectiveDeadZone
        guard remainingRange > 0.0001 else { return 0 }

        let normalized = min(max((clampedVal - effectiveDeadZone) / remainingRange, 0.0), 1.0)

        // Apply sensitivity curve: value = pow(normalizedValue, 1.0 / sensitivity)
        let safeSensitivity = max(sensitivity, 0.1)
        let curved = pow(normalized, 1.0 / safeSensitivity)

        return UInt8(min(max((curved * 255.0).rounded(), 0.0), 255.0))
    }

    // MARK: - Button Remapping

    /// Resolves button remappings defined in the active profile's `buttonMapping` dictionary.
    ///
    /// - Parameter source: The source button bitmask.
    /// - Returns: The target button bitmask, or the original if unmapped.
    private func resolveRemappedButton(_ source: ButtonMask) -> ButtonMask {
        let mapping = profileService.activeProfile.buttonMapping
        guard !mapping.isEmpty else { return source }

        // Look up by displayName (e.g. "A", "B", "X", "Y", "LB", "RB", etc.)
        let sourceKey = source.displayName
        if let targetName = mapping[sourceKey] ?? mapping[sourceKey.lowercased()] {
            if let matched = ButtonMask.allCases.first(where: {
                $0.displayName.caseInsensitiveCompare(targetName) == .orderedSame
                || "\($0.rawValue)" == targetName
            }) {
                return matched
            }
        }

        return source
    }
}
