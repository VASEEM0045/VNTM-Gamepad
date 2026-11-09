//
//  CalibrationView.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//  MVVM Architecture with Combine Framework
//

import SwiftUI

/// Interactive hardware testing, diagnostics, and analog trim calibration view.
///
/// Features a real-time HUD visualizer at the top, step-by-step interactive verification
/// for dual thumbsticks, analog triggers (0-255), digital action buttons, and 8-way D-pad directions,
/// with progress tracking, calibration offset saving, and tactile testing feedback.
public struct CalibrationView: View {

    // MARK: - Injected ViewModels

    @EnvironmentObject private var controllerVM: GameControllerViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Verification Tracking State

    @State private var testedButtons: Set<ButtonMask> = []
    @State private var testedDPadDirections: Set<DPadDirection> = []

    // Stick Range Tracking
    @State private var leftStickMinReached: Bool = false
    @State private var leftStickMaxReached: Bool = false
    @State private var rightStickMinReached: Bool = false
    @State private var rightStickMaxReached: Bool = false

    // Trigger Range Tracking
    @State private var leftTriggerMaxReached: Bool = false
    @State private var rightTriggerMaxReached: Bool = false

    // Save Confirmation Feedback
    @State private var isSavedAlertShowing: Bool = false

    // MARK: - Constants

    private let totalVerificationPoints = 9 + 8 + 4 + 2 // 9 buttons + 8 D-pad + 4 stick axes + 2 triggers = 23

    // MARK: - Initialization

    public init() {}

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Background
            Color(hex: 0x0B0E14)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: 1. Full Real-Time Input Visualizer HUD
                    visualizerHeader

                    // MARK: 2. Verification Progress Bar & Banner
                    progressHeaderCard

                    // MARK: 3. Thumbstick Range Calibration Test
                    analogSticksTestCard

                    // MARK: 4. Analog Trigger Test (0-255)
                    analogTriggersTestCard

                    // MARK: 5. Digital Buttons Verification Grid
                    buttonsTestCard

                    // MARK: 6. 8-Direction D-Pad Test
                    dpadTestCard

                    // MARK: 7. Calibration Actions Toolbar
                    actionButtonsToolbar

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Calibration & Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
            }
        }
        .alert("Calibration Saved", isPresented: $isSavedAlertShowing) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Hardware zero-point trims and boundary calibrations have been successfully saved to '\(settingsVM.activeProfile.name)'.")
        }
        // Observe live controller state updates to automatically verify inputs
        .onChange(of: controllerVM.controllerState.buttons) { buttons in
            evaluateButtonMasks(buttons)
        }
        .onChange(of: controllerVM.controllerState.dpadState) { dpad in
            if dpad != .center {
                testedDPadDirections.insert(dpad)
            }
        }
        .onChange(of: controllerVM.controllerState.leftStickX) { val in
            evaluateStickRanges()
        }
        .onChange(of: controllerVM.controllerState.leftTrigger) { val in
            if val >= 240 { leftTriggerMaxReached = true }
        }
        .onChange(of: controllerVM.controllerState.rightTrigger) { val in
            if val >= 240 { rightTriggerMaxReached = true }
        }
    }

    // MARK: - 1. Top HUD Visualizer

    private var visualizerHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("LIVE INPUT HUD", systemImage: "eye.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                Text("READ-ONLY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: 0x2A75D3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(hex: 0x2A75D3).opacity(0.15)))
            }
            .padding(.horizontal, 4)

            // Embedded full InputVisualizerView component
            InputVisualizerView(state: controllerVM.controllerState)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(white: 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - 2. Progress Header

    private var verifiedCount: Int {
        var count = testedButtons.count + testedDPadDirections.count
        if leftStickMinReached && leftStickMaxReached { count += 2 } else if leftStickMinReached || leftStickMaxReached { count += 1 }
        if rightStickMinReached && rightStickMaxReached { count += 2 } else if rightStickMinReached || rightStickMaxReached { count += 1 }
        if leftTriggerMaxReached { count += 1 }
        if rightTriggerMaxReached { count += 1 }
        return count
    }

    private var progressFraction: Double {
        Double(verifiedCount) / Double(totalVerificationPoints)
    }

    private var progressHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calibration Verification")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Verify all analog extremes and button actuation.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(verifiedCount) / \(totalVerificationPoints)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(progressFraction >= 1.0 ? Color(hex: 0x2ECC71) : Color(hex: 0x2A75D3))
            }

            // Progress Bar
            GeometryReader { p in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(white: 0.18))
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: progressFraction >= 1.0 ?
                                    [Color(hex: 0x2ECC71), Color(hex: 0x27AE60)] :
                                    [Color(hex: 0x2A75D3), Color(hex: 0x00FFCC)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, p.size.width * CGFloat(progressFraction)), height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progressFraction)
                }
            }
            .frame(height: 8)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.11))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    // MARK: - 3. Analog Sticks Test

    private var analogSticksTestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("ANALOG THUMBSTICKS", systemImage: "circle.grid.cross")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                if leftStickMinReached && leftStickMaxReached && rightStickMinReached && rightStickMaxReached {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("FULL RANGE")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: 0x2ECC71))
                }
            }

            Text("Rotate both thumbsticks to verify full circular boundary deflection (-1.0 to 1.0).")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                // Left Stick Interactive Test Pad
                VStack(spacing: 8) {
                    Text("Left Stick")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    AnalogStickView(
                        size: 130,
                        deadZone: CGFloat(settingsVM.activeProfile.deadZones.leftStickDeadZone)
                    ) { x, y in
                        controllerVM.updateLeftStick(x: x, y: y)
                    }

                    HStack(spacing: 8) {
                        rangeIndicator(title: "MIN", reached: leftStickMinReached)
                        rangeIndicator(title: "MAX", reached: leftStickMaxReached)
                    }

                    Text("X: \(controllerVM.controllerState.leftStickX)  Y: \(controllerVM.controllerState.leftStickY)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .background(Color.white.opacity(0.1))

                // Right Stick Interactive Test Pad
                VStack(spacing: 8) {
                    Text("Right Stick")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    AnalogStickView(
                        size: 130,
                        deadZone: CGFloat(settingsVM.activeProfile.deadZones.rightStickDeadZone)
                    ) { x, y in
                        controllerVM.updateRightStick(x: x, y: y)
                    }

                    HStack(spacing: 8) {
                        rangeIndicator(title: "MIN", reached: rightStickMinReached)
                        rangeIndicator(title: "MAX", reached: rightStickMaxReached)
                    }

                    Text("X: \(controllerVM.controllerState.rightStickX)  Y: \(controllerVM.controllerState.rightStickY)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.11))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private func rangeIndicator(title: String, reached: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(reached ? Color(hex: 0x2ECC71) : .secondary)

            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(reached ? .white : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(reached ? Color(hex: 0x2ECC71).opacity(0.2) : Color.white.opacity(0.05)))
    }

    // MARK: - 4. Analog Triggers Test

    private var analogTriggersTestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("ANALOG TRIGGERS (0 - 255)", systemImage: "slider.vertical.3")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                if leftTriggerMaxReached && rightTriggerMaxReached {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("CALIBRATED")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: 0x2ECC71))
                }
            }

            Text("Squeeze both triggers fully to verify travel reaches maximum depth (255 byte).")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)

            HStack(spacing: 24) {
                // Left Trigger (LT)
                VStack(spacing: 8) {
                    TriggerView(label: "LT", side: .left, width: 56, height: 100) { val in
                        controllerVM.updateLeftTrigger(value: val)
                    }

                    Text("Value: \(controllerVM.controllerState.leftTrigger) / 255")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(leftTriggerMaxReached ? Color(hex: 0x2ECC71) : .white)

                    rangeIndicator(title: "MAX 255", reached: leftTriggerMaxReached)
                }
                .frame(maxWidth: .infinity)

                // Right Trigger (RT)
                VStack(spacing: 8) {
                    TriggerView(label: "RT", side: .right, width: 56, height: 100) { val in
                        controllerVM.updateRightTrigger(value: val)
                    }

                    Text("Value: \(controllerVM.controllerState.rightTrigger) / 255")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(rightTriggerMaxReached ? Color(hex: 0x2ECC71) : .white)

                    rangeIndicator(title: "MAX 255", reached: rightTriggerMaxReached)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.11))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    // MARK: - 5. Digital Buttons Test

    private var buttonsTestCard: some View {
        let testButtons: [ButtonMask] = [
            .a, .b, .x, .y,
            .lb, .rb,
            .start, .select, .home
        ]

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("DIGITAL BUTTONS (\(testedButtons.count) / \(testButtons.count))", systemImage: "circle.grid.2x2")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                if testedButtons.count == testButtons.count {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("ALL VERIFIED")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: 0x2ECC71))
                }
            }

            Text("Tap each button to verify digital contact actuation and haptic feedback.")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)

            // Grid of Buttons
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(testButtons, id: \.self) { mask in
                    buttonTestItem(mask: mask)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.11))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private func buttonTestItem(mask: ButtonMask) -> some View {
        let isVerified = testedButtons.contains(mask)
        let isCurrentlyPressed = (controllerVM.controllerState.buttons & mask.rawValue) != 0

        return Button {
            // Test actuation
            testedButtons.insert(mask)
            controllerVM.updateButton(mask, pressed: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                controllerVM.updateButton(mask, pressed: false)
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isCurrentlyPressed ? Color(hex: 0x2ECC71) : (isVerified ? Color(hex: 0x2ECC71).opacity(0.2) : Color.white.opacity(0.08)))
                        .frame(width: 28, height: 28)

                    if isVerified {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isCurrentlyPressed ? .black : Color(hex: 0x2ECC71))
                    }
                }

                Text(mask.displayName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(isCurrentlyPressed ? Color(hex: 0x2ECC71) : .white)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCurrentlyPressed ? Color(hex: 0x2ECC71).opacity(0.18) : Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isVerified ? Color(hex: 0x2ECC71).opacity(0.4) : Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 6. D-Pad Test

    private var dpadTestCard: some View {
        let allDirections: [DPadDirection] = [
            .up, .upRight, .right, .downRight,
            .down, .downLeft, .left, .upLeft
        ]

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("8-DIRECTIONAL D-PAD (\(testedDPadDirections.count) / 8)", systemImage: "dpad.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                if testedDPadDirections.count == 8 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("ALL 8 VERIFIED")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: 0x2ECC71))
                }
            }

            Text("Press and drag the D-pad across all cardinal and diagonal sectors.")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                // Interactive D-Pad
                DPadView(size: 130) { dir in
                    controllerVM.updateDPad(direction: dir)
                    if dir != .center {
                        testedDPadDirections.insert(dir)
                    }
                }
                .frame(maxWidth: .infinity)

                // Direction Check Grid
                VStack(spacing: 6) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                        ForEach(allDirections, id: \.self) { dir in
                            let reached = testedDPadDirections.contains(dir)
                            HStack(spacing: 4) {
                                Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(reached ? Color(hex: 0x2ECC71) : .secondary)

                                Text(dpadTitle(dir))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(reached ? .white : .secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(reached ? Color(hex: 0x2ECC71).opacity(0.12) : Color.white.opacity(0.04)))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.11))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private func dpadTitle(_ dir: DPadDirection) -> String {
        switch dir {
        case .up: return "Up"
        case .upRight: return "Up-Right"
        case .right: return "Right"
        case .downRight: return "Down-Right"
        case .down: return "Down"
        case .downLeft: return "Down-Left"
        case .left: return "Left"
        case .upLeft: return "Up-Left"
        case .center: return "Center"
        }
    }

    // MARK: - 7. Action Buttons Toolbar

    private var actionButtonsToolbar: some View {
        VStack(spacing: 12) {
            // Save Calibration Button
            Button {
                saveCalibration()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Save Calibration")
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0x2ECC71), Color(hex: 0x27AE60)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(14)
                .shadow(color: Color(hex: 0x2ECC71).opacity(0.3), radius: 6, x: 0, y: 3)
            }

            // Reset Calibration Button
            Button {
                resetCalibration()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Test Checkpoints")
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Helper Logic

    private func evaluateButtonMasks(_ bitmask: UInt32) {
        for mask in ButtonMask.allCases {
            if (bitmask & mask.rawValue) != 0 {
                testedButtons.insert(mask)
            }
        }
    }

    private func evaluateStickRanges() {
        let lx = controllerVM.controllerState.leftStickX
        let ly = controllerVM.controllerState.leftStickY
        let rx = controllerVM.controllerState.rightStickX
        let ry = controllerVM.controllerState.rightStickY

        if lx <= 20 || ly <= 20 { leftStickMinReached = true }
        if lx >= 235 || ly >= 235 { leftStickMaxReached = true }

        if rx <= 20 || ry <= 20 { rightStickMinReached = true }
        if rx >= 235 || ry >= 235 { rightStickMaxReached = true }
    }

    private func saveCalibration() {
        var profile = settingsVM.activeProfile
        profile.calibration.isCalibrated = true
        settingsVM.activeProfile = profile
        isSavedAlertShowing = true
    }

    private func resetCalibration() {
        testedButtons.removeAll()
        testedDPadDirections.removeAll()
        leftStickMinReached = false
        leftStickMaxReached = false
        rightStickMinReached = false
        rightStickMaxReached = false
        leftTriggerMaxReached = false
        rightTriggerMaxReached = false

        var profile = settingsVM.activeProfile
        profile.calibration.reset()
        settingsVM.activeProfile = profile
    }
}

#if DEBUG
struct CalibrationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CalibrationView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
