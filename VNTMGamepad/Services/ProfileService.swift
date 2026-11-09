//
//  ProfileService.swift
//  VNTM Gamepad
//
//  Profile management service responsible for loading, persisting, duplicating,
//  importing/exporting, and switching controller layouts and configurations.
//

import Foundation
import Combine
import os.log

/// Errors that can occur during profile operations.
public enum ProfileServiceError: LocalizedError {
    case profileNotFound(UUID)
    case cannotDeleteLastProfile
    case decodingFailed(Error)
    case encodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .profileNotFound(let id):
            return "Controller profile with ID \(id.uuidString) was not found."
        case .cannotDeleteLastProfile:
            return "Cannot delete the only remaining controller profile."
        case .decodingFailed(let error):
            return "Failed to parse controller profile data: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to serialize controller profile: \(error.localizedDescription)"
        }
    }
}

/// Service managing controller profiles, layouts, button remapping, and sensitivity configurations.
///
/// Automatically seeds three built-in factory defaults ('Default Classic', 'Arcade Fighter', 'Racing')
/// on first run and persists modifications to UserDefaults as JSON.
public final class ProfileService: ObservableObject {

    // MARK: - Constants

    /// Key for persisting the array of profiles in UserDefaults.
    public static let profilesStorageKey = "vntm.profiles.v1"

    /// Key for persisting the currently active profile identifier.
    public static let activeProfileStorageKey = "vntm.profiles.activeID"

    /// Stable UUIDs for factory preset profiles.
    public static let defaultClassicID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    public static let arcadeFighterID  = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    public static let racingID         = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    // MARK: - Factory Presets

    /// Generates the three built-in default controller profiles.
    public static var factoryDefaults: [ControllerProfile] {
        [
            ControllerProfile(
                id: defaultClassicID,
                name: "Default Classic",
                layout: .classic,
                sensitivity: .default,
                deadZones: .default
            ),
            ControllerProfile(
                id: arcadeFighterID,
                name: "Arcade Fighter",
                layout: .arcade,
                sensitivity: .default,
                deadZones: .default
            ),
            ControllerProfile(
                id: racingID,
                name: "Racing",
                layout: .racing,
                sensitivity: .default,
                deadZones: .default
            )
        ]
    }

    // MARK: - Published Properties

    /// All available controller profiles.
    @Published public private(set) var profiles: [ControllerProfile] = []

    /// The currently selected active controller profile.
    @Published public private(set) var activeProfile: ControllerProfile

    // MARK: - Private Properties

    /// Key-value storage interface.
    private let userDefaults: UserDefaults

    /// Native unified logger.
    private let logger = Logger(subsystem: "com.vntm.gamepad", category: "Profile")

    // MARK: - Initialization

    /// Initializes a new ProfileService instance.
    /// - Parameter userDefaults: Key-value storage for profile persistence (defaults to `.standard`).
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load profiles from storage or seed defaults
        let loadedProfiles = Self.loadStoredProfiles(from: userDefaults)
        let resolvedProfiles = loadedProfiles.isEmpty ? Self.factoryDefaults : loadedProfiles
        self.profiles = resolvedProfiles

        // Determine active profile from persisted ID or fall back to first profile
        let savedActiveID = userDefaults.string(forKey: Self.activeProfileStorageKey)
            .flatMap { UUID(uuidString: $0) }

        if let savedID = savedActiveID,
           let matched = resolvedProfiles.first(where: { $0.id == savedID }) {
            self.activeProfile = matched
        } else {
            self.activeProfile = resolvedProfiles.first ?? Self.factoryDefaults[0]
        }

        // Persist initial state if we seeded defaults
        if loadedProfiles.isEmpty {
            saveProfilesToStorage()
        }

        AppLog.info("ProfileService initialized with \(self.profiles.count) profile(s). Active: '\(self.activeProfile.name)'", category: .profile)
    }

    // MARK: - Profile Management API

    /// Creates and persists a new custom profile.
    /// - Parameter name: Display name for the new profile.
    /// - Returns: The newly created `ControllerProfile`.
    @discardableResult
    public func createProfile(name: String) -> ControllerProfile {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Custom Profile" : trimmedName

        let newProfile = ControllerProfile(
            id: UUID(),
            name: finalName,
            layout: .custom,
            buttonMapping: activeProfile.buttonMapping,
            sensitivity: activeProfile.sensitivity,
            deadZones: activeProfile.deadZones,
            calibration: activeProfile.calibration,
            customLayout: ControllerProfile.defaultCustomLayout
        )

        profiles.append(newProfile)
        saveProfilesToStorage()

        logger.info("Created new profile '\(newProfile.name)' [\(newProfile.id.uuidString)]")
        AppLog.info("Created profile '\(newProfile.name)'.", category: .profile)

        return newProfile
    }

    /// Deletes a profile by its unique identifier.
    /// - Parameter id: The UUID of the profile to remove.
    public func deleteProfile(id: UUID) {
        guard profiles.count > 1 else {
            logger.warning("Attempted to delete the last remaining profile.")
            AppLog.warning("Cannot delete the only remaining profile.", category: .profile)
            return
        }

        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            logger.warning("Profile to delete not found: \(id.uuidString)")
            return
        }

        let deleted = profiles.remove(at: index)
        logger.info("Deleted profile '\(deleted.name)' [\(deleted.id.uuidString)]")
        AppLog.info("Deleted profile '\(deleted.name)'.", category: .profile)

        // If the active profile was deleted, switch to the first available profile
        if activeProfile.id == id {
            let nextActive = profiles.first!
            setActiveProfile(id: nextActive.id)
        } else {
            saveProfilesToStorage()
        }
    }

    /// Duplicates an existing profile.
    /// - Parameter id: The identifier of the profile to clone.
    /// - Returns: The newly created duplicate `ControllerProfile`, or `nil` if not found.
    @discardableResult
    public func duplicateProfile(id: UUID) -> ControllerProfile? {
        guard let original = profiles.first(where: { $0.id == id }) else {
            logger.warning("Cannot duplicate: profile not found for id \(id.uuidString)")
            return nil
        }

        let duplicate = ControllerProfile(
            id: UUID(),
            name: "\(original.name) Copy",
            layout: original.layout,
            buttonMapping: original.buttonMapping,
            sensitivity: original.sensitivity,
            deadZones: original.deadZones,
            calibration: original.calibration,
            customLayout: original.customLayout,
            createdAt: Date(),
            updatedAt: Date()
        )

        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles.insert(duplicate, at: index + 1)
        } else {
            profiles.append(duplicate)
        }

        saveProfilesToStorage()
        logger.info("Duplicated profile '\(original.name)' as '\(duplicate.name)' [\(duplicate.id.uuidString)]")
        AppLog.info("Duplicated profile '\(original.name)'.", category: .profile)

        return duplicate
    }

    /// Sets the currently active controller profile.
    /// - Parameter id: The identifier of the profile to activate.
    public func setActiveProfile(id: UUID) {
        guard let target = profiles.first(where: { $0.id == id }) else {
            logger.warning("Cannot activate profile: ID not found \(id.uuidString)")
            return
        }

        activeProfile = target
        userDefaults.set(target.id.uuidString, forKey: Self.activeProfileStorageKey)

        logger.info("Activated profile '\(target.name)' [\(target.id.uuidString)]")
        AppLog.info("Switched to profile: '\(target.name)'.", category: .profile)
    }

    /// Updates and persists changes to an existing profile.
    /// - Parameter updatedProfile: The modified `ControllerProfile`.
    public func updateProfile(_ updatedProfile: ControllerProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == updatedProfile.id }) else {
            logger.warning("Cannot update profile: ID not found \(updatedProfile.id.uuidString)")
            return
        }

        var fixed = updatedProfile.repaired()
        fixed.updatedAt = Date()

        profiles[index] = fixed

        if activeProfile.id == fixed.id {
            activeProfile = fixed
        }

        saveProfilesToStorage()
        logger.info("Updated profile '\(fixed.name)' [\(fixed.id.uuidString)]")
    }

    /// Exports a profile to JSON data for sharing or backup.
    /// - Parameter id: The identifier of the profile to export.
    /// - Returns: Pretty-printed JSON encoded `Data`.
    public func exportProfile(id: UUID) throws -> Data {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw ProfileServiceError.profileNotFound(id)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(profile)
            logger.info("Exported profile '\(profile.name)' (\(data.count) bytes)")
            AppLog.info("Exported profile '\(profile.name)'.", category: .profile)
            return data
        } catch {
            logger.error("Failed to encode profile: \(error.localizedDescription)")
            throw ProfileServiceError.encodingFailed(error)
        }
    }

    /// Imports a controller profile from JSON data.
    /// - Parameter data: Raw JSON data representing a `ControllerProfile`.
    /// - Returns: The parsed and persisted `ControllerProfile`.
    @discardableResult
    public func importProfile(from data: Data) throws -> ControllerProfile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            var imported = try decoder.decode(ControllerProfile.self, from: data)

            // Ensure imported profile has a unique ID if one already collides
            if profiles.contains(where: { $0.id == imported.id }) {
                imported.id = UUID()
                imported.name = "\(imported.name) (Imported)"
            }

            // Defensively repair out-of-range bounds
            let sanitized = imported.repaired()

            profiles.append(sanitized)
            saveProfilesToStorage()

            logger.info("Imported profile '\(sanitized.name)' [\(sanitized.id.uuidString)]")
            AppLog.info("Imported profile '\(sanitized.name)'.", category: .profile)

            return sanitized
        } catch {
            logger.error("Failed to decode profile: \(error.localizedDescription)")
            AppLog.error("Profile import failed: \(error.localizedDescription)", category: .profile)
            throw ProfileServiceError.decodingFailed(error)
        }
    }

    /// Resets all profiles back to factory defaults.
    public func resetToDefaults() {
        profiles = Self.factoryDefaults
        activeProfile = Self.factoryDefaults[0]
        saveProfilesToStorage()

        logger.info("Profiles reset to factory defaults.")
        AppLog.info("All profiles reset to factory defaults.", category: .profile)
    }

    // MARK: - Persistence Helpers

    /// Loads saved profiles from UserDefaults.
    private static func loadStoredProfiles(from defaults: UserDefaults) -> [ControllerProfile] {
        guard let data = defaults.data(forKey: profilesStorageKey) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let decoded = try decoder.decode([ControllerProfile].self, from: data)
            return decoded.map { $0.repaired() }
        } catch {
            AppLog.error("Error decoding stored profiles: \(error.localizedDescription)", category: .profile)
            return []
        }
    }

    /// Persists current profiles and active ID to UserDefaults.
    private func saveProfilesToStorage() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(profiles)
            userDefaults.set(data, forKey: Self.profilesStorageKey)
            userDefaults.set(activeProfile.id.uuidString, forKey: Self.activeProfileStorageKey)
        } catch {
            logger.error("Failed to save profiles to storage: \(error.localizedDescription)")
            AppLog.error("Failed to save profiles: \(error.localizedDescription)", category: .profile)
        }
    }
}
