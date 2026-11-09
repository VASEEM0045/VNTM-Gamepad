//
//  SettingsViewModel.swift
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

/// ViewModel responsible for managing user preferences, controller configuration profiles,
/// sensitivity and dead zone calibrations, haptic tactile intensity, visual themes,
/// layout customization, and onboarding first-launch state.
@MainActor
public final class SettingsViewModel: ObservableObject {

    // MARK: - Constants

    /// UserDefaults key tracking first launch onboarding completion.
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    /// UserDefaults key for motion control preference.
    private static let motionEnabledKey = "motionEnabled"

    /// UserDefaults key for haptic feedback toggle.
    private static let hapticEnabledKey = "hapticEnabled"

    // MARK: - Published Properties

    /// The currently active controller profile being edited or played.
    @Published public var activeProfile: ControllerProfile

    /// All stored user and factory preset controller profiles.
    @Published public var profiles: [ControllerProfile] = []

    /// Current visual skin and accent theme for controller overlay and app chrome.
    @Published public var selectedTheme: ThemeType = .dark

    /// Master toggle controlling whether haptic feedback vibrations are enabled.
    @Published public var hapticEnabled: Bool = true

    /// Master tactile vibration scale factor (range: 0.0 - 1.0).
    @Published public var hapticIntensity: Double = 1.0

    /// Master toggle for enabling tilt-based gyroscopic motion steering.
    @Published public var motionEnabled: Bool = false

    /// Controls presentation of the welcome/onboarding sheet on initial app launch.
    @Published public var showOnboarding: Bool = false

    // MARK: - Injected Dependencies

    private let profileService: ProfileService
    private let hapticService: HapticService
    private let userDefaults: UserDefaults

    // MARK: - Private State

    /// Retained Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Native unified system logger.
    private let logger = Logger(subsystem: "com.vntm.gamepad", category: "SettingsViewModel")

    // MARK: - Initialization

    /// Initializes a new SettingsViewModel instance with injected profile and haptic services.
    ///
    /// - Parameters:
    ///   - profileService: Profile persistence and lifecycle manager.
    ///   - hapticService: CoreHaptics tactile feedback engine.
    ///   - userDefaults: Key-value storage interface (defaults to `.standard`).
    public init(
        profileService: ProfileService,
        hapticService: HapticService,
        userDefaults: UserDefaults = .standard
    ) {
        self.profileService = profileService
        self.hapticService = hapticService
        self.userDefaults = userDefaults

        // 1. Initialize profile snapshots
        self.activeProfile = profileService.activeProfile
        self.profiles = profileService.profiles
        self.selectedTheme = profileService.activeProfile.theme

        // 2. Initialize haptic state
        let currentIntensity = Double(hapticService.intensity)
        self.hapticIntensity = currentIntensity
        let isHapticSaved = userDefaults.object(forKey: Self.hapticEnabledKey) as? Bool ?? true
        self.hapticEnabled = isHapticSaved && (currentIntensity > 0.0)

        // 3. Initialize motion control toggle
        self.motionEnabled = userDefaults.bool(forKey: Self.motionEnabledKey)

        // 4. Initialize first launch onboarding check
        let hasCompleted = userDefaults.bool(forKey: Self.hasCompletedOnboardingKey)
        self.showOnboarding = !hasCompleted

        setupSubscriptions()
        logger.info("SettingsViewModel initialized. Active Profile: '\(self.activeProfile.name)', ShowOnboarding: \(self.showOnboarding)")
    }

    // MARK: - Combine Subscriptions

    /// Subscribes to ProfileService and HapticService publishers to keep UI properties synchronized.
    private func setupSubscriptions() {
        // Observe profile library changes
        profileService.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedProfiles in
                guard let self = self else { return }
                self.profiles = updatedProfiles
            }
            .store(in: &cancellables)

        // Observe active profile modifications
        profileService.$activeProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newActiveProfile in
                guard let self = self else { return }
                self.activeProfile = newActiveProfile
                self.selectedTheme = newActiveProfile.theme
            }
            .store(in: &cancellables)

        // Observe hardware haptic intensity changes
        hapticService.$intensity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newIntensity in
                guard let self = self else { return }
                let doubleVal = Double(newIntensity)
                self.hapticIntensity = doubleVal
                self.hapticEnabled = doubleVal > 0.0
            }
            .store(in: &cancellables)
    }

    // MARK: - Sensitivity & Dead Zone Adjustments

    /// Updates the sensitivity multiplier for a thumbstick, trigger, or motion sensor, saving immediately.
    ///
    /// - Parameters:
    ///   - stick: Component identifier: `"left"`, `"right"`, `"leftTrigger"`, `"rightTrigger"`, or `"motion"`.
    ///   - value: New sensitivity scale factor (supported range: 0.1 to 3.0).
    public func updateSensitivity(stick: String, value: Double) {
        let clamped = min(max(value, 0.1), 3.0)
        let key = stick.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch key {
        case "left", "leftstick", "ls":
            activeProfile.sensitivity.leftStickSensitivity = clamped
        case "right", "rightstick", "rs":
            activeProfile.sensitivity.rightStickSensitivity = clamped
        case "lefttrigger", "lt":
            activeProfile.sensitivity.leftTriggerSensitivity = clamped
        case "righttrigger", "rt":
            activeProfile.sensitivity.rightTriggerSensitivity = clamped
        case "motion", "gyro":
            activeProfile.sensitivity.motionSensitivity = clamped
        default:
            logger.warning("Unrecognized sensitivity target identifier: '\(stick)'")
            return
        }

        profileService.updateProfile(activeProfile)
        logger.debug("Updated sensitivity for '\(stick)' to \(clamped)")
    }

    /// Updates the dead zone threshold for an analog stick or trigger, saving immediately.
    ///
    /// - Parameters:
    ///   - stick: Component identifier: `"left"`, `"right"`, `"leftTrigger"`, or `"rightTrigger"`.
    ///   - value: New dead zone threshold (supported range: 0.0 to 0.5).
    public func updateDeadZone(stick: String, value: Double) {
        let clamped = DeadZoneSettings.clamp(value)
        let key = stick.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch key {
        case "left", "leftstick", "ls":
            activeProfile.deadZones.leftStickDeadZone = clamped
        case "right", "rightstick", "rs":
            activeProfile.deadZones.rightStickDeadZone = clamped
        case "lefttrigger", "lt":
            activeProfile.deadZones.leftTriggerDeadZone = clamped
        case "righttrigger", "rt":
            activeProfile.deadZones.rightTriggerDeadZone = clamped
        default:
            logger.warning("Unrecognized dead zone target identifier: '\(stick)'")
            return
        }

        profileService.updateProfile(activeProfile)
        logger.debug("Updated dead zone for '\(stick)' to \(clamped)")
    }

    // MARK: - Haptic Adjustments

    /// Adjusts tactile vibration strength across the app and active profile, persisting immediately.
    ///
    /// - Parameter value: New haptic intensity (0.0 to 1.0).
    public func updateHapticIntensity(_ value: Double) {
        let clamped = min(max(value, 0.0), 1.0)
        hapticIntensity = clamped
        hapticEnabled = clamped > 0.0

        hapticService.intensity = Float(clamped)
        activeProfile.hapticIntensity = clamped
        profileService.updateProfile(activeProfile)

        userDefaults.set(clamped, forKey: "vntm.haptics.intensity")
        userDefaults.set(hapticEnabled, forKey: Self.hapticEnabledKey)
        logger.debug("Haptic intensity set to \(clamped)")
    }

    /// Toggles haptic vibrations on or off.
    public func toggleHapticEnabled() {
        hapticEnabled.toggle()
        userDefaults.set(hapticEnabled, forKey: Self.hapticEnabledKey)

        if hapticEnabled {
            let restoreIntensity = hapticIntensity > 0.0 ? hapticIntensity : 1.0
            updateHapticIntensity(restoreIntensity)
        } else {
            hapticService.intensity = 0.0
            hapticService.stopAll()
        }
        logger.info("Haptics toggled: \(self.hapticEnabled)")
    }

    // MARK: - Motion Control Adjustments

    /// Toggles the motion controls master switch and persists preference to UserDefaults.
    public func toggleMotionEnabled() {
        motionEnabled.toggle()
        userDefaults.set(motionEnabled, forKey: Self.motionEnabledKey)
        logger.info("Motion controls master toggle: \(self.motionEnabled)")
    }

    // MARK: - Profile Management

    /// Selects and activates an existing profile by its unique identifier.
    ///
    /// - Parameter id: The UUID of the target profile.
    public func switchProfile(id: UUID) {
        profileService.setActiveProfile(id: id)
        logger.info("Switched active profile to ID: \(id.uuidString)")
    }

    /// Creates and persists a new custom profile seeded with standard defaults.
    ///
    /// - Parameter name: Friendly display title for the new profile.
    public func createNewProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileName = trimmed.isEmpty ? "New Profile" : trimmed
        let created = profileService.createProfile(name: profileName)
        switchProfile(id: created.id)
        logger.info("Created new profile: '\(profileName)' (ID: \(created.id.uuidString))")
    }

    /// Permanently removes a custom controller profile.
    ///
    /// - Parameter id: The UUID of the profile to delete.
    public func deleteProfile(id: UUID) {
        profileService.deleteProfile(id: id)
        logger.info("Deleted profile ID: \(id.uuidString)")
    }

    /// Duplicates an existing profile for customized experimentation.
    ///
    /// - Parameter id: The UUID of the profile to clone.
    public func duplicateProfile(id: UUID) {
        if let clone = profileService.duplicateProfile(id: id) {
            switchProfile(id: clone.id)
            logger.info("Duplicated profile to ID: \(clone.id.uuidString)")
        }
    }

    /// Reverts all stored configurations and active profile to factory preset defaults.
    public func resetToDefaults() {
        profileService.resetToDefaults()
        updateHapticIntensity(1.0)
        hapticEnabled = true
        motionEnabled = false
        userDefaults.set(false, forKey: Self.motionEnabledKey)
        logger.info("Reset all settings and profiles to factory defaults.")
    }

    /// Serializes the active profile into a JSON data payload for sharing or backup.
    ///
    /// - Returns: Encoded binary JSON data, or empty data on failure.
    public func exportProfile() -> Data {
        do {
            let data = try profileService.exportProfile(id: activeProfile.id)
            logger.info("Successfully exported profile '\(self.activeProfile.name)'.")
            return data
        } catch {
            logger.error("Failed to export profile: \(error.localizedDescription)")
            return Data()
        }
    }

    /// Imports a controller profile from JSON data and activates it.
    ///
    /// - Parameter data: Encoded binary JSON profile representation.
    public func importProfile(data: Data) {
        do {
            let imported = try profileService.importProfile(from: data)
            switchProfile(id: imported.id)
            logger.info("Successfully imported profile: '\(imported.name)'")
        } catch {
            logger.error("Failed to import profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Visual Styling & Theme

    /// Updates the color theme of the controller HUD and active profile.
    ///
    /// - Parameter theme: The desired visual theme preset.
    public func updateTheme(_ theme: ThemeType) {
        selectedTheme = theme
        activeProfile.theme = theme
        profileService.updateProfile(activeProfile)
        logger.debug("Visual theme updated to: \(theme.displayName)")
    }

    /// Updates the on-screen controller overlay HUD opacity (range: 0.3 - 1.0).
    ///
    /// - Parameter value: Desired alpha opacity value.
    public func updateOverlayOpacity(_ value: Double) {
        let clamped = min(max(value, 0.3), 1.0)
        activeProfile.overlayOpacity = clamped
        profileService.updateProfile(activeProfile)
        logger.debug("Controller overlay opacity updated to: \(clamped)")
    }

    /// Updates the visual layout arrangement preset (classic, arcade, racing, custom).
    ///
    /// - Parameter layout: Target layout preset.
    public func updateLayout(_ layout: LayoutType) {
        activeProfile.layout = layout
        profileService.updateProfile(activeProfile)
        logger.info("Active layout updated to: \(layout.displayName)")
    }

    // MARK: - Onboarding Lifecycle

    /// Marks the initial welcome onboarding flow as completed.
    public func completeOnboarding() {
        showOnboarding = false
        userDefaults.set(true, forKey: Self.hasCompletedOnboardingKey)
        logger.info("First-launch onboarding marked as completed.")
    }
}
