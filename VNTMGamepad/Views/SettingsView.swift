//
//  SettingsView.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//  MVVM Architecture with Combine Framework
//

import SwiftUI

/// Comprehensive configuration and preferences screen.
///
/// Provides profile management (create, duplicate, delete), layout selection,
/// analog stick and trigger sensitivity calibration, radial dead zones, CoreHaptics tuning,
/// gyroscopic motion steering, theme personalization, and diagnostic navigation.
public struct SettingsView: View {

    // MARK: - Injected ViewModels

    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var controllerVM: GameControllerViewModel

    // MARK: - Local Alert & Dialog State

    @State private var isShowingCreateProfileAlert: Bool = false
    @State private var newProfileName: String = ""
    @State private var isShowingResetAlert: Bool = false
    @State private var isShowingExportSheet: Bool = false
    @State private var exportedData: Data? = nil

    // MARK: - Initialization

    public init() {}

    // MARK: - Body

    public var body: some View {
        Form {
            // MARK: 1. Profile Management Section
            profileSection

            // MARK: 2. Layout Arrangement Section
            layoutSection

            // MARK: 3. Input Calibration Link
            calibrationLinkSection

            // MARK: 4. Sensitivity Section
            sensitivitySection

            // MARK: 5. Dead Zone Section
            deadZoneSection

            // MARK: 6. Tactile Haptics Section
            hapticsSection

            // MARK: 7. Gyroscope & Motion Controls Section
            motionControlsSection

            // MARK: 8. Appearance & Theme Section
            appearanceSection

            // MARK: 9. Profile Transfer & Backup
            transferSection

            // MARK: 10. About & Legal Section
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        // Create Profile Alert Dialog
        .alert("Create New Profile", isPresented: $isShowingCreateProfileAlert) {
            TextField("Profile Name (e.g. Flight Sim)", text: $newProfileName)
            Button("Cancel", role: .cancel) {
                newProfileName = ""
            }
            Button("Create") {
                settingsVM.createNewProfile(name: newProfileName)
                newProfileName = ""
            }
        } message: {
            Text("Enter a unique title for your new customized controller layout and tuning settings.")
        }
        // Reset to Factory Defaults Confirmation
        .alert("Reset All Settings?", isPresented: $isShowingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset to Defaults", role: .destructive) {
                settingsVM.resetToDefaults()
            }
        } message: {
            Text("All custom profiles, button mappings, sensitivities, and calibrations will be restored to factory defaults. This action cannot be undone.")
        }
    }

    // MARK: - 1. Profile Section

    private var profileSection: some View {
        Section(
            header: Label("Controller Profile", systemImage: "person.crop.circle"),
            footer: Text("Profiles preserve custom button remappings, sensitivity curves, and dead zones.")
        ) {
            // Profile Selector Picker
            Picker("Active Profile", selection: Binding(
                get: { settingsVM.activeProfile.id },
                set: { newID in settingsVM.switchProfile(id: newID) }
            )) {
                ForEach(settingsVM.profiles) { profile in
                    HStack {
                        Text(profile.name)
                        if profile.id == settingsVM.activeProfile.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                    .tag(profile.id)
                }
            }

            // Profile Actions
            HStack(spacing: 12) {
                // Create New Button
                Button {
                    newProfileName = ""
                    isShowingCreateProfileAlert = true
                } label: {
                    Label("New Profile", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                }

                Spacer()

                // Duplicate Button
                Button {
                    settingsVM.duplicateProfile(id: settingsVM.activeProfile.id)
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .regular))
                }

                Spacer()

                // Delete Button
                Button(role: .destructive) {
                    settingsVM.deleteProfile(id: settingsVM.activeProfile.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 14, weight: .regular))
                }
                .disabled(settingsVM.profiles.count <= 1)
            }
        }
    }

    // MARK: - 2. Layout Section

    private var layoutSection: some View {
        Section(
            header: Label("Controller Layout", systemImage: "gamecontroller"),
            footer: Text("Select an optimized control layout tailored for your game genre.")
        ) {
            Picker("Layout Type", selection: Binding(
                get: { settingsVM.activeProfile.layout },
                set: { newLayout in settingsVM.updateLayout(newLayout) }
            )) {
                ForEach(LayoutType.allCases) { layout in
                    HStack {
                        Image(systemName: layout.symbolName)
                        Text(layout.displayName)
                    }
                    .tag(layout)
                }
            }
            .pickerStyle(.segmented)

            // Layout Preview Card
            layoutPreviewCard(layout: settingsVM.activeProfile.layout)
                .padding(.vertical, 4)
        }
    }

    private func layoutPreviewCard(layout: LayoutType) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.16))
                    .frame(width: 52, height: 52)

                Image(systemName: layout.symbolName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: 0x2A75D3))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(layout.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(layout.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.10))
        )
    }

    // MARK: - 3. Calibration Link Section

    private var calibrationLinkSection: some View {
        Section(header: Label("Diagnostics", systemImage: "waveform.path.ecg")) {
            NavigationLink(destination: CalibrationView()) {
                HStack(spacing: 12) {
                    Image(systemName: "tuningfork")
                        .foregroundColor(Color(hex: 0x2ECC71))
                        .font(.system(size: 16, weight: .semibold))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hardware Calibration & Testing")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Test analog extremes, trigger range, and button response.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if settingsVM.activeProfile.calibration.isCalibrated {
                        Text("CALIBRATED")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: 0x2ECC71))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: 0x2ECC71).opacity(0.15)))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 4. Sensitivity Section

    private var sensitivitySection: some View {
        Section(
            header: Label("Analog Sensitivity", systemImage: "gauge.badge.plus"),
            footer: Text("Adjust the response curve multiplier. Higher values produce faster deflection response.")
        ) {
            // Left Stick Sensitivity
            sliderRow(
                title: "Left Thumbstick",
                value: settingsVM.activeProfile.sensitivity.leftStickSensitivity,
                range: 0.1...3.0,
                format: "%.1fx",
                onChanged: { val in settingsVM.updateSensitivity(stick: "left", value: val) }
            )

            // Right Stick Sensitivity
            sliderRow(
                title: "Right Thumbstick",
                value: settingsVM.activeProfile.sensitivity.rightStickSensitivity,
                range: 0.1...3.0,
                format: "%.1fx",
                onChanged: { val in settingsVM.updateSensitivity(stick: "right", value: val) }
            )

            // Left Trigger Sensitivity
            sliderRow(
                title: "Left Trigger (LT)",
                value: settingsVM.activeProfile.sensitivity.leftTriggerSensitivity,
                range: 0.1...3.0,
                format: "%.1fx",
                onChanged: { val in settingsVM.updateSensitivity(stick: "leftTrigger", value: val) }
            )

            // Right Trigger Sensitivity
            sliderRow(
                title: "Right Trigger (RT)",
                value: settingsVM.activeProfile.sensitivity.rightTriggerSensitivity,
                range: 0.1...3.0,
                format: "%.1fx",
                onChanged: { val in settingsVM.updateSensitivity(stick: "rightTrigger", value: val) }
            )
        }
    }

    // MARK: - 5. Dead Zone Section

    private var deadZoneSection: some View {
        Section(
            header: Label("Radial Dead Zones", systemImage: "circle.slash"),
            footer: Text("Dead zones filter out minor stick drift and accidental thumb rest contact.")
        ) {
            // Left Stick Dead Zone
            sliderRow(
                title: "Left Stick Dead Zone",
                value: settingsVM.activeProfile.deadZones.leftStickDeadZone,
                range: 0.0...0.5,
                format: "%.0f%%",
                displayMultiplier: 100.0,
                onChanged: { val in settingsVM.updateDeadZone(stick: "left", value: val) }
            )

            // Right Stick Dead Zone
            sliderRow(
                title: "Right Stick Dead Zone",
                value: settingsVM.activeProfile.deadZones.rightStickDeadZone,
                range: 0.0...0.5,
                format: "%.0f%%",
                displayMultiplier: 100.0,
                onChanged: { val in settingsVM.updateDeadZone(stick: "right", value: val) }
            )

            // Left Trigger Dead Zone
            sliderRow(
                title: "Left Trigger (LT) Dead Zone",
                value: settingsVM.activeProfile.deadZones.leftTriggerDeadZone,
                range: 0.0...0.5,
                format: "%.0f%%",
                displayMultiplier: 100.0,
                onChanged: { val in settingsVM.updateDeadZone(stick: "leftTrigger", value: val) }
            )

            // Right Trigger Dead Zone
            sliderRow(
                title: "Right Trigger (RT) Dead Zone",
                value: settingsVM.activeProfile.deadZones.rightTriggerDeadZone,
                range: 0.0...0.5,
                format: "%.0f%%",
                displayMultiplier: 100.0,
                onChanged: { val in settingsVM.updateDeadZone(stick: "rightTrigger", value: val) }
            )
        }
    }

    // MARK: - 6. Haptics Section

    private var hapticsSection: some View {
        Section(
            header: Label("Tactile Haptics", systemImage: "waveform"),
            footer: Text("CoreHaptics provides realistic transient button clicks and progressive analog trigger drag resistance.")
        ) {
            Toggle("Haptic Feedback Vibrations", isOn: Binding(
                get: { settingsVM.hapticEnabled },
                set: { _ in settingsVM.toggleHapticEnabled() }
            ))

            if settingsVM.hapticEnabled {
                sliderRow(
                    title: "Vibration Intensity",
                    value: settingsVM.hapticIntensity,
                    range: 0.1...1.0,
                    format: "%.0f%%",
                    displayMultiplier: 100.0,
                    onChanged: { val in settingsVM.updateHapticIntensity(val) }
                )
            }
        }
    }

    // MARK: - 7. Motion Controls Section

    private var motionControlsSection: some View {
        Section(
            header: Label("Motion Controls (Gyro)", systemImage: "gyroscope"),
            footer: Text("Uses the internal 6-axis gyroscope for tilt-based steering and look aiming.")
        ) {
            Toggle("Enable Motion Controls", isOn: Binding(
                get: { settingsVM.motionEnabled },
                set: { _ in settingsVM.toggleMotionEnabled() }
            ))

            if settingsVM.motionEnabled {
                sliderRow(
                    title: "Gyro Sensitivity",
                    value: settingsVM.activeProfile.sensitivity.motionSensitivity,
                    range: 0.1...3.0,
                    format: "%.1fx",
                    onChanged: { val in settingsVM.updateSensitivity(stick: "motion", value: val) }
                )
            }
        }
    }

    // MARK: - 8. Appearance Section

    private var appearanceSection: some View {
        Section(
            header: Label("Appearance & HUD", systemImage: "paintpalette"),
            footer: Text("Select an accent theme and configure the controller overlay transparency for distraction-free gameplay.")
        ) {
            // Theme Picker
            Picker("Theme", selection: Binding(
                get: { settingsVM.selectedTheme },
                set: { newTheme in settingsVM.updateTheme(newTheme) }
            )) {
                ForEach(ThemeType.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }

            // Overlay Opacity Slider
            sliderRow(
                title: "HUD Overlay Opacity",
                value: settingsVM.activeProfile.overlayOpacity,
                range: 0.3...1.0,
                format: "%.0f%%",
                displayMultiplier: 100.0,
                onChanged: { val in settingsVM.updateOverlayOpacity(val) }
            )
        }
    }

    // MARK: - 9. Transfer & Backup Section

    private var transferSection: some View {
        Section(header: Label("Profile Backup", systemImage: "square.and.arrow.up")) {
            Button {
                exportedData = settingsVM.exportProfile()
                isShowingExportSheet = true
            } label: {
                Label("Export Active Profile (JSON)", systemImage: "square.and.arrow.up")
            }

            Button {
                // Factory default reset
                isShowingResetAlert = true
            } label: {
                Label("Reset to Factory Defaults", systemImage: "arrow.counterclockwise")
                    .foregroundColor(Color(hex: 0xE74C3C))
            }
        }
    }

    // MARK: - 10. About Section

    private var aboutSection: some View {
        Section(header: Label("About", systemImage: "info.circle")) {
            HStack {
                Text("Application")
                Spacer()
                Text(AppConstants.appName)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Version")
                Spacer()
                Text("\(AppConstants.version) (Build \(AppConstants.build))")
                    .foregroundColor(.secondary)
            }

            Link(destination: AppConstants.supportURL) {
                HStack {
                    Text("Help & Support")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Link(destination: AppConstants.privacyPolicyURL) {
                HStack {
                    Text("Privacy Policy")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Slider Helper Row

    private func sliderRow(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        format: String,
        displayMultiplier: Double = 1.0,
        onChanged: @escaping (Double) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))

                Spacer()

                Text(String(format: format, value * displayMultiplier))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: 0x2A75D3))
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { newVal in onChanged(newVal) }
                ),
                in: range
            )
            .accentColor(Color(hex: 0x2A75D3))
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
