//
//  HapticService.swift
//  VNTM Gamepad
//
//  Tactile feedback engine delivering rich, responsive haptic textures via
//  CoreHaptics with seamless fallback to UIKit feedback generators on
//  unsupported hardware or older devices.
//

import Foundation
import CoreHaptics
import UIKit
import Combine
import os.log

/// Service managing tactile feedback across the controller interface.
///
/// Features custom CoreHaptics transient and continuous pattern generation for
/// buttons, analog sticks, trigger pulls, and connection events, with automatic
/// fallback to UIKit impact and notification feedback generators.
public final class HapticService: ObservableObject {

    // MARK: - Constants

    /// Key for persisting user haptic intensity preference in UserDefaults.
    private static let intensityKey = "vntm.haptics.intensity"

    // MARK: - Published Properties

    /// Whether advanced haptic feedback is supported and available on this hardware.
    @Published public private(set) var isAvailable: Bool = false

    /// Master haptic intensity scale factor (range: 0.0 - 1.0).
    @Published public var intensity: Float {
        didSet {
            let clamped = min(max(intensity, 0.0), 1.0)
            if clamped != intensity {
                intensity = clamped
            }
            userDefaults.set(clamped, forKey: Self.intensityKey)
            logger.debug("Haptic intensity updated: \(clamped)")
        }
    }

    // MARK: - Private Properties

    /// Active CoreHaptics engine instance.
    private var engine: CHHapticEngine?

    /// Continuous pattern player used for analog trigger feedback.
    private var triggerPlayer: CHHapticAdvancedPatternPlayer?

    /// Fallback UIKit feedback generators.
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    /// Key-value storage for settings.
    private let userDefaults: UserDefaults

    /// Native unified logger.
    private let logger = Logger(subsystem: "com.vntm.gamepad", category: "Haptics")

    // MARK: - Initialization

    /// Initializes a new HapticService instance.
    /// - Parameter userDefaults: Key-value storage (defaults to `.standard`).
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load saved intensity or default to 1.0 (full strength)
        let savedIntensity = userDefaults.object(forKey: Self.intensityKey) as? Float ?? 1.0
        self.intensity = min(max(savedIntensity, 0.0), 1.0)

        prepareEngine()
        AppLog.info("HapticService initialized. Hardware support: \(self.isAvailable)", category: .haptics)
    }

    deinit {
        stopAll()
    }

    // MARK: - Engine Lifecycle

    /// Prepares and starts the CoreHaptics engine, setting up lifecycle handlers.
    public func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            logger.info("CoreHaptics unsupported on this hardware. Falling back to UIKit feedback generators.")
            isAvailable = false
            prepareFallbackGenerators()
            return
        }

        do {
            let engine = try CHHapticEngine()
            self.engine = engine

            // Handle backgrounding or audio interruption stops
            engine.stoppedHandler = { [weak self] reason in
                self?.logger.warning("CoreHaptics engine stopped: \(reason.rawValue)")
                AppLog.warning("Haptic engine stopped.", category: .haptics)
            }

            // Handle engine reset (e.g., returning from background)
            engine.resetHandler = { [weak self] in
                self?.logger.info("CoreHaptics engine resetting. Restarting...")
                AppLog.info("Haptic engine resetting.", category: .haptics)
                do {
                    try self?.engine?.start()
                } catch {
                    self?.logger.error("Failed to restart CoreHaptics engine: \(error.localizedDescription)")
                }
            }

            try engine.start()
            isAvailable = true
            logger.info("CoreHaptics engine started successfully.")
            AppLog.info("CoreHaptics engine active.", category: .haptics)
        } catch {
            logger.error("Failed to initialize CoreHaptics engine: \(error.localizedDescription)")
            AppLog.error("Haptic engine initialization failed: \(error.localizedDescription)", category: .haptics)
            isAvailable = false
            prepareFallbackGenerators()
        }
    }

    /// Prepares UIKit fallback generators for low-latency firing.
    private func prepareFallbackGenerators() {
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        notificationGenerator.prepare()
    }

    // MARK: - Public Haptic Patterns

    /// Plays a sharp, crisp tactile tap for button down / press events.
    public func playButtonPress() {
        guard intensity > 0 else { return }

        guard isAvailable, let engine = engine else {
            mediumImpactGenerator.impactOccurred()
            return
        }

        do {
            let hapticIntensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: 0.85 * intensity
            )
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 0.90
            )

            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [hapticIntensity, sharpness],
                relativeTime: 0
            )

            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            logger.error("Error playing button press haptic: \(error.localizedDescription)")
            mediumImpactGenerator.impactOccurred()
        }
    }

    /// Plays continuous tactile feedback for analog triggers, scaling intensity with pull pressure.
    /// - Parameter pressure: Trigger displacement in the range 0.0 (rest) to 1.0 (fully depressed).
    public func playTriggerFeedback(pressure: Float) {
        let clampedPressure = min(max(pressure, 0.0), 1.0)
        let effectiveIntensity = clampedPressure * intensity

        guard effectiveIntensity > 0.02 else {
            // Stop trigger vibration if pressure drops to resting zone
            stopTriggerFeedback()
            return
        }

        guard isAvailable, let engine = engine else {
            // Fallback for UIKit impact generator with dynamic intensity
            heavyImpactGenerator.impactOccurred(intensity: CGFloat(effectiveIntensity))
            return
        }

        do {
            // If continuous player already exists, update its dynamic parameters
            if let player = triggerPlayer {
                let dynamicIntensity = CHHapticDynamicParameter(
                    parameterID: .hapticIntensityControl,
                    value: effectiveIntensity,
                    relativeTime: 0
                )
                let dynamicSharpness = CHHapticDynamicParameter(
                    parameterID: .hapticSharpnessControl,
                    value: 0.3 + (clampedPressure * 0.4),
                    relativeTime: 0
                )
                try player.sendParameters([dynamicIntensity, dynamicSharpness], atTime: CHHapticTimeImmediate)
            } else {
                // Otherwise create a new continuous player
                let hapticIntensity = CHHapticEventParameter(
                    parameterID: .hapticIntensity,
                    value: effectiveIntensity
                )
                let sharpness = CHHapticEventParameter(
                    parameterID: .hapticSharpness,
                    value: 0.3 + (clampedPressure * 0.4)
                )

                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [hapticIntensity, sharpness],
                    relativeTime: 0,
                    duration: 1.5
                )

                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makeAdvancedPlayer(with: pattern)
                self.triggerPlayer = player
                try player.start(atTime: CHHapticTimeImmediate)
            }
        } catch {
            logger.error("Error playing trigger feedback: \(error.localizedDescription)")
            heavyImpactGenerator.impactOccurred(intensity: CGFloat(effectiveIntensity))
        }
    }

    /// Stops any active continuous trigger feedback.
    private func stopTriggerFeedback() {
        guard let player = triggerPlayer else { return }
        try? player.stop(atTime: CHHapticTimeImmediate)
        triggerPlayer = nil
    }

    /// Plays a subtle bump sensation when an analog stick reaches its physical boundary/edge.
    public func playStickBoundary() {
        guard intensity > 0 else { return }

        guard isAvailable, let engine = engine else {
            lightImpactGenerator.impactOccurred(intensity: CGFloat(0.5 * intensity))
            return
        }

        do {
            let hapticIntensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: 0.45 * intensity
            )
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 0.25
            )

            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [hapticIntensity, sharpness],
                relativeTime: 0
            )

            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            logger.error("Error playing stick boundary haptic: \(error.localizedDescription)")
            lightImpactGenerator.impactOccurred(intensity: CGFloat(0.5 * intensity))
        }
    }

    /// Plays a distinct multi-tap pattern indicating connection or disconnection events.
    /// - Parameter connected: `true` for connection established; `false` for disconnection.
    public func playConnectionEvent(connected: Bool) {
        guard intensity > 0 else { return }

        guard isAvailable, let engine = engine else {
            notificationGenerator.notificationOccurred(connected ? .success : .warning)
            return
        }

        do {
            var events: [CHHapticEvent] = []

            if connected {
                // Rising pleasant double-tap
                let tap1 = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5 * intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                    ],
                    relativeTime: 0.0
                )
                let tap2 = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9 * intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85)
                    ],
                    relativeTime: 0.12
                )
                events = [tap1, tap2]
            } else {
                // Descending double thud
                let thud1 = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8 * intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                    ],
                    relativeTime: 0.0
                )
                let thud2 = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4 * intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: 0.14
                )
                events = [thud1, thud2]
            }

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            logger.error("Error playing connection event haptic: \(error.localizedDescription)")
            notificationGenerator.notificationOccurred(connected ? .success : .warning)
        }
    }

    /// Plays a distinct error pattern consisting of three rapid high-sharpness pulses.
    public func playError() {
        guard intensity > 0 else { return }

        guard isAvailable, let engine = engine else {
            notificationGenerator.notificationOccurred(.error)
            return
        }

        do {
            let pulses = (0..<3).map { index -> CHHapticEvent in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.95 * intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.95)
                    ],
                    relativeTime: Double(index) * 0.08
                )
            }

            let pattern = try CHHapticPattern(events: pulses, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            logger.error("Error playing error haptic: \(error.localizedDescription)")
            notificationGenerator.notificationOccurred(.error)
        }
    }

    /// Stops all ongoing haptic sensations and releases active players.
    public func stopAll() {
        stopTriggerFeedback()
        try? engine?.stop()
        isAvailable = false
    }
}
