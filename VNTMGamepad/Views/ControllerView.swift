//
//  ControllerView.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//  MVVM Architecture with Combine Framework
//

import SwiftUI
import UIKit

/// The primary full-screen landscape game controller interface.
///
/// Features low-latency touch controls, dynamic layout configurations (.classic, .arcade, .racing, .custom),
/// real-time wireless connection telemetry, and user-configurable overlay transparency.
public struct ControllerView: View {

    // MARK: - Injected ViewModels

    @EnvironmentObject private var controllerVM: GameControllerViewModel
    @EnvironmentObject private var connectionVM: ConnectionViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    // MARK: - Button State Bindings

    @State private var isAPressed: Bool = false
    @State private var isBPressed: Bool = false
    @State private var isXPressed: Bool = false
    @State private var isYPressed: Bool = false
    @State private var isLBPressed: Bool = false
    @State private var isRBPressed: Bool = false
    @State private var isStartPressed: Bool = false
    @State private var isSelectPressed: Bool = false
    @State private var isHomePressed: Bool = false

    // Arcade Extra Buttons
    @State private var isArcadeExtra1Pressed: Bool = false
    @State private var isArcadeExtra2Pressed: Bool = false

    // Racing Wheel State
    @State private var steeringAngle: Double = 0.0
    @State private var isSteeringDragging: Bool = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background & Ambience
                backgroundLayer

                // Main Controller Canvas with User Configured Opacity
                VStack(spacing: 0) {
                    // Top Telemetry & Status Bar
                    topBarLayer
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    Spacer(minLength: 4)

                    // Active Controller Layout
                    activeLayoutView(in: geometry)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
                .opacity(settingsVM.activeProfile.overlayOpacity)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            lockOrientation(to: .landscapeRight)
        }
        .onDisappear {
            restoreOrientation()
        }
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        ZStack {
            // Dark Gaming Base Gradient
            LinearGradient(
                colors: [
                    Color(hex: 0x090C10),
                    Color(hex: 0x0F141C),
                    Color(hex: 0x06080B)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle Theme Accent Glow
            RadialGradient(
                colors: [
                    themeColor.opacity(0.12),
                    Color.clear
                ],
                center: .top,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()

            // Outer Controller Grip Subtle Contours
            HStack {
                // Left Palm Grip Contour
                RoundedRectangle(cornerRadius: 40)
                    .fill(Color.white.opacity(0.015))
                    .frame(width: 90)
                    .blur(radius: 10)
                    .offset(x: -30)

                Spacer()

                // Right Palm Grip Contour
                RoundedRectangle(cornerRadius: 40)
                    .fill(Color.white.opacity(0.015))
                    .frame(width: 90)
                    .blur(radius: 10)
                    .offset(x: 30)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Top Telemetry Bar

    private var topBarLayer: some View {
        HStack(spacing: 12) {
            // Live Connection Status Bar
            ConnectionStatusBar(
                status: connectionVM.status,
                metrics: connectionVM.metrics,
                connectionType: connectionVM.connectionType,
                onTap: {
                    // Quick scan retry if disconnected
                    if connectionVM.status == .disconnected {
                        connectionVM.startScanning()
                    }
                }
            )

            Spacer()

            // Layout & Sensor Shortcuts
            HStack(spacing: 8) {
                // Motion Controls Indicator/Toggle
                Button {
                    controllerVM.toggleMotionControls()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gyroscope")
                            .font(.system(size: 13, weight: .semibold))
                        Text(controllerVM.isMotionActive ? "GYRO ON" : "GYRO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(controllerVM.isMotionActive ? Color(hex: 0x00FFCC) : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(controllerVM.isMotionActive ? Color(hex: 0x00FFCC).opacity(0.2) : Color.white.opacity(0.06))
                    )
                }

                // Hardware Calibration Modal Button
                Button {
                    controllerVM.showCalibration = true
                } label: {
                    Image(systemName: "tuningfork")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }

                // Active Profile Pill
                Menu {
                    ForEach(settingsVM.profiles) { profile in
                        Button {
                            settingsVM.switchProfile(id: profile.id)
                        } label: {
                            HStack {
                                Text(profile.name)
                                if profile.id == settingsVM.activeProfile.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: controllerVM.activeLayout.symbolName)
                            .font(.system(size: 11, weight: .bold))
                        Text(settingsVM.activeProfile.name)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.16))
                            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                    )
                }
            }
        }
        .frame(height: 38)
    }

    // MARK: - Active Layout Switcher

    @ViewBuilder
    private func activeLayoutView(in geometry: GeometryProxy) -> some View {
        switch controllerVM.activeLayout {
        case .classic, .custom:
            classicLayout(in: geometry)
        case .arcade:
            arcadeLayout(in: geometry)
        case .racing:
            racingLayout(in: geometry)
        }
    }

    // MARK: - Layout 1: Classic Xbox Layout

    private func classicLayout(in geometry: GeometryProxy) -> some View {
        HStack(alignment: .center, spacing: 0) {
            // MARK: Left Hand Side (Shoulder + D-Pad + Left Thumbstick)
            VStack(spacing: 10) {
                // Left Shoulders (LB + LT)
                leftShouldersView

                Spacer()

                // Left Stick & D-Pad Arranged Xbox-Style (Stick lower, D-pad upper or offset)
                HStack(alignment: .bottom, spacing: 18) {
                    // D-Pad (Top Left relative positioning)
                    DPadView(size: 126) { direction in
                        controllerVM.updateDPad(direction: direction)
                    }

                    // Left Analog Stick (Bottom Left offset)
                    AnalogStickView(
                        size: 136,
                        deadZone: CGFloat(settingsVM.activeProfile.deadZones.leftStickDeadZone)
                    ) { x, y in
                        controllerVM.updateLeftStick(x: x, y: y)
                    }
                }
            }
            .frame(maxWidth: geometry.size.width * 0.42)

            Spacer()

            // MARK: Center Hub (Select + Home/Xbox + Start)
            centerHubView
                .frame(width: geometry.size.width * 0.16)

            Spacer()

            // MARK: Right Hand Side (Shoulders + Diamond ABXY + Right Thumbstick)
            VStack(spacing: 10) {
                // Right Shoulders (RB + RT)
                rightShouldersView

                Spacer()

                // Diamond Action Buttons & Right Stick
                HStack(alignment: .bottom, spacing: 18) {
                    // Right Analog Stick (Bottom-ish position)
                    AnalogStickView(
                        size: 136,
                        deadZone: CGFloat(settingsVM.activeProfile.deadZones.rightStickDeadZone)
                    ) { x, y in
                        controllerVM.updateRightStick(x: x, y: y)
                    }

                    // Diamond Action Buttons (Y top, X left, B right, A bottom)
                    diamondActionButtons(size: 54)
                }
            }
            .frame(maxWidth: geometry.size.width * 0.42)
        }
    }

    // MARK: - Layout 2: Arcade Fightstick Layout

    private func arcadeLayout(in geometry: GeometryProxy) -> some View {
        HStack(alignment: .center, spacing: 0) {
            // MARK: Left Side (D-Pad + Left Analog Stick)
            VStack(spacing: 14) {
                // Left Shoulder Bumper (LB)
                HStack {
                    shoulderBumper(label: "LB", isPressed: $isLBPressed, mask: .lb)
                    Spacer()
                }

                Spacer()

                HStack(spacing: 20) {
                    // Primary Arcade D-Pad
                    DPadView(size: 140) { direction in
                        controllerVM.updateDPad(direction: direction)
                    }

                    // Secondary Analog Stick
                    AnalogStickView(
                        size: 120,
                        deadZone: CGFloat(settingsVM.activeProfile.deadZones.leftStickDeadZone)
                    ) { x, y in
                        controllerVM.updateLeftStick(x: x, y: y)
                    }
                }
            }
            .frame(maxWidth: geometry.size.width * 0.38)

            Spacer()

            // Center Auxiliary Controls
            centerHubView
                .frame(width: geometry.size.width * 0.14)

            Spacer()

            // MARK: Right Side (6 Action Buttons in 2 Rows of 3)
            VStack(spacing: 14) {
                // Right Shoulder Bumper (RB)
                HStack {
                    Spacer()
                    shoulderBumper(label: "RB", isPressed: $isRBPressed, mask: .rb)
                }

                Spacer()

                // 6 Arcade Fight Buttons (2 rows of 3)
                VStack(spacing: 12) {
                    // Top Row: X (Light Punch), Y (Medium Punch), RT (Heavy Punch)
                    HStack(spacing: 16) {
                        VirtualButton(
                            label: "X",
                            buttonColor: Color(hex: 0x2A75D3), // Blue
                            size: 58,
                            isPressed: $isXPressed,
                            onPress: { controllerVM.updateButton(.x, pressed: true) },
                            onRelease: { controllerVM.updateButton(.x, pressed: false) }
                        )

                        VirtualButton(
                            label: "Y",
                            buttonColor: Color(hex: 0xF1C40F), // Yellow
                            size: 58,
                            isPressed: $isYPressed,
                            onPress: { controllerVM.updateButton(.y, pressed: true) },
                            onRelease: { controllerVM.updateButton(.y, pressed: false) }
                        )

                        VirtualButton(
                            label: "RT",
                            buttonColor: Color(hex: 0x9B59B6), // Purple
                            size: 58,
                            isPressed: $isArcadeExtra1Pressed,
                            onPress: {
                                controllerVM.updateRightTrigger(value: 1.0)
                            },
                            onRelease: {
                                controllerVM.updateRightTrigger(value: 0.0)
                            }
                        )
                    }

                    // Bottom Row: A (Light Kick), B (Medium Kick), LT (Heavy Kick)
                    HStack(spacing: 16) {
                        VirtualButton(
                            label: "A",
                            buttonColor: Color(hex: 0x2ECC71), // Green
                            size: 58,
                            isPressed: $isAPressed,
                            onPress: { controllerVM.updateButton(.a, pressed: true) },
                            onRelease: { controllerVM.updateButton(.a, pressed: false) }
                        )

                        VirtualButton(
                            label: "B",
                            buttonColor: Color(hex: 0xE74C3C), // Red
                            size: 58,
                            isPressed: $isBPressed,
                            onPress: { controllerVM.updateButton(.b, pressed: true) },
                            onRelease: { controllerVM.updateButton(.b, pressed: false) }
                        )

                        VirtualButton(
                            label: "LT",
                            buttonColor: Color(hex: 0xE67E22), // Orange
                            size: 58,
                            isPressed: $isArcadeExtra2Pressed,
                            onPress: {
                                controllerVM.updateLeftTrigger(value: 1.0)
                            },
                            onRelease: {
                                controllerVM.updateLeftTrigger(value: 0.0)
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: geometry.size.width * 0.44)
        }
    }

    // MARK: - Layout 3: Racing Layout (Steering Wheel + Gas/Brake Pedals)

    private func racingLayout(in geometry: GeometryProxy) -> some View {
        HStack(alignment: .center, spacing: 0) {
            // MARK: Left: Rotational Steering Wheel & Downshift Paddle
            VStack(spacing: 8) {
                // Left Paddle Shifter (LB / Downshift)
                HStack {
                    paddleShifter(label: "◀ DOWNSHIFT (LB)", isPressed: $isLBPressed, mask: .lb)
                    Spacer()
                }

                Spacer()

                // Interactive Rotational Steering Wheel
                steeringWheelView(size: min(geometry.size.height * 0.72, 220))

                Spacer()
            }
            .frame(maxWidth: geometry.size.width * 0.44)

            Spacer()

            // Center Auxiliary Controls & Horn
            VStack(spacing: 16) {
                centerHubView

                // Center Horn Button
                VirtualButton(
                    label: "HORN",
                    buttonColor: Color(hex: 0xE67E22),
                    size: 50,
                    isPressed: $isHomePressed,
                    onPress: { controllerVM.updateButton(.home, pressed: true) },
                    onRelease: { controllerVM.updateButton(.home, pressed: false) }
                )
            }
            .frame(width: geometry.size.width * 0.16)

            Spacer()

            // MARK: Right: Upshift Paddle & Gas / Brake Pedals
            VStack(spacing: 8) {
                // Right Paddle Shifter (RB / Upshift)
                HStack {
                    Spacer()
                    paddleShifter(label: "(RB) UPSHIFT ▶", isPressed: $isRBPressed, mask: .rb)
                }

                Spacer()

                // Dual Analog Pedals (Brake LT + Throttle RT)
                HStack(spacing: 28) {
                    // Brake Pedal (LT)
                    VStack(spacing: 6) {
                        TriggerView(label: "BRAKE", side: .left, width: 68, height: 140) { value in
                            controllerVM.updateLeftTrigger(value: value)
                        }
                    }

                    // Gas / Throttle Pedal (RT)
                    VStack(spacing: 6) {
                        TriggerView(label: "GAS", side: .right, width: 68, height: 140) { value in
                            controllerVM.updateRightTrigger(value: value)
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: geometry.size.width * 0.38)
        }
    }

    // MARK: - Subcomponents: Shoulders

    private var leftShouldersView: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left Bumper (LB)
            shoulderBumper(label: "LB", isPressed: $isLBPressed, mask: .lb)

            // Left Trigger (LT)
            TriggerView(label: "LT", side: .left, width: 54, height: 90) { value in
                controllerVM.updateLeftTrigger(value: value)
            }

            Spacer()
        }
    }

    private var rightShouldersView: some View {
        HStack(alignment: .top, spacing: 12) {
            Spacer()

            // Right Trigger (RT)
            TriggerView(label: "RT", side: .right, width: 54, height: 90) { value in
                controllerVM.updateRightTrigger(value: value)
            }

            // Right Bumper (RB)
            shoulderBumper(label: "RB", isPressed: $isRBPressed, mask: .rb)
        }
    }

    private func shoulderBumper(label: String, isPressed: Binding<Bool>, mask: ButtonMask) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: isPressed.wrappedValue ?
                            [Color(white: 0.22), Color(white: 0.15)] :
                            [Color(white: 0.32), Color(white: 0.20)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 76, height: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(isPressed.wrappedValue ? 0.3 : 0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 2)

            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .scaleEffect(isPressed.wrappedValue ? 0.94 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: isPressed.wrappedValue)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed.wrappedValue {
                        isPressed.wrappedValue = true
                        controllerVM.updateButton(mask, pressed: true)
                    }
                }
                .onEnded { _ in
                    if isPressed.wrappedValue {
                        isPressed.wrappedValue = false
                        controllerVM.updateButton(mask, pressed: false)
                    }
                }
        )
    }

    private func paddleShifter(label: String, isPressed: Binding<Bool>, mask: ButtonMask) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: isPressed.wrappedValue ?
                            [Color(hex: 0xE74C3C), Color(hex: 0xC0392B)] :
                            [Color(white: 0.25), Color(white: 0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 140, height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
        }
        .scaleEffect(isPressed.wrappedValue ? 0.94 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: isPressed.wrappedValue)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed.wrappedValue {
                        isPressed.wrappedValue = true
                        controllerVM.updateButton(mask, pressed: true)
                    }
                }
                .onEnded { _ in
                    if isPressed.wrappedValue {
                        isPressed.wrappedValue = false
                        controllerVM.updateButton(mask, pressed: false)
                    }
                }
        )
    }

    // MARK: - Subcomponents: Center Hub

    private var centerHubView: some View {
        VStack(spacing: 14) {
            // Small Top Center Buttons: Select + Start
            HStack(spacing: 24) {
                // Select / Back / View
                centerPillButton(
                    icon: "square.split.2x1",
                    label: "VIEW",
                    isPressed: $isSelectPressed,
                    mask: .select
                )

                // Start / Menu
                centerPillButton(
                    icon: "line.3.horizontal",
                    label: "MENU",
                    isPressed: $isStartPressed,
                    mask: .start
                )
            }

            // Illuminated Xbox/Home Button
            homeJewelButton
        }
    }

    private func centerPillButton(
        icon: String,
        label: String,
        isPressed: Binding<Bool>,
        mask: ButtonMask
    ) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(isPressed.wrappedValue ? Color(white: 0.20) : Color(white: 0.14))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.8))

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isPressed.wrappedValue ? .white : .secondary)
            }

            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .scaleEffect(isPressed.wrappedValue ? 0.90 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: isPressed.wrappedValue)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed.wrappedValue {
                        isPressed.wrappedValue = true
                        controllerVM.updateButton(mask, pressed: true)
                    }
                }
                .onEnded { _ in
                    if isPressed.wrappedValue {
                        isPressed.wrappedValue = false
                        controllerVM.updateButton(mask, pressed: false)
                    }
                }
        )
    }

    private var homeJewelButton: some View {
        ZStack {
            // Outer Jewel Halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            controllerVM.isConnected ? Color(hex: 0x2ECC71).opacity(0.35) : Color.white.opacity(0.10),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 26
                    )
                )
                .frame(width: 52, height: 52)

            // Button Body
            Circle()
                .fill(
                    LinearGradient(
                        colors: isHomePressed ?
                            [Color(white: 0.12), Color(white: 0.08)] :
                            [Color(white: 0.22), Color(white: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 42, height: 42)
                .overlay(
                    Circle()
                        .stroke(
                            controllerVM.isConnected ? Color(hex: 0x2ECC71).opacity(0.8) : Color.white.opacity(0.3),
                            lineWidth: 1.5
                        )
                )

            // Xbox / VNTM Glyph
            Image(systemName: "circle.grid.cross.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(controllerVM.isConnected ? Color(hex: 0x2ECC71) : .white)
        }
        .scaleEffect(isHomePressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: isHomePressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isHomePressed {
                        isHomePressed = true
                        controllerVM.updateButton(.home, pressed: true)
                    }
                }
                .onEnded { _ in
                    if isHomePressed {
                        isHomePressed = false
                        controllerVM.updateButton(.home, pressed: false)
                    }
                }
        )
    }

    // MARK: - Subcomponents: Diamond ABXY Action Buttons

    private func diamondActionButtons(size: CGFloat) -> some View {
        ZStack {
            // Y Button (Top - Yellow)
            VirtualButton(
                label: "Y",
                buttonColor: Color(hex: 0xF1C40F),
                size: size,
                isPressed: $isYPressed,
                onPress: { controllerVM.updateButton(.y, pressed: true) },
                onRelease: { controllerVM.updateButton(.y, pressed: false) }
            )
            .offset(y: -size * 0.90)

            // X Button (Left - Blue)
            VirtualButton(
                label: "X",
                buttonColor: Color(hex: 0x2A75D3),
                size: size,
                isPressed: $isXPressed,
                onPress: { controllerVM.updateButton(.x, pressed: true) },
                onRelease: { controllerVM.updateButton(.x, pressed: false) }
            )
            .offset(x: -size * 0.90)

            // B Button (Right - Red)
            VirtualButton(
                label: "B",
                buttonColor: Color(hex: 0xE74C3C),
                size: size,
                isPressed: $isBPressed,
                onPress: { controllerVM.updateButton(.b, pressed: true) },
                onRelease: { controllerVM.updateButton(.b, pressed: false) }
            )
            .offset(x: size * 0.90)

            // A Button (Bottom - Green)
            VirtualButton(
                label: "A",
                buttonColor: Color(hex: 0x2ECC71),
                size: size,
                isPressed: $isAPressed,
                onPress: { controllerVM.updateButton(.a, pressed: true) },
                onRelease: { controllerVM.updateButton(.a, pressed: false) }
            )
            .offset(y: size * 0.90)
        }
        .frame(width: size * 2.8, height: size * 2.8)
    }

    // MARK: - Subcomponents: Racing Steering Wheel

    private func steeringWheelView(size: CGFloat) -> some View {
        GeometryReader { wheelProxy in
            let center = CGPoint(x: wheelProxy.size.width / 2, y: wheelProxy.size.height / 2)

            ZStack {
                // Outer Steering Rim
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color(white: 0.35), Color(white: 0.15), Color(white: 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: size * 0.14
                    )
                    .frame(width: size, height: size)
                    .shadow(color: Color.black.opacity(0.6), radius: 8, x: 0, y: 4)

                // Top 12-o'clock Red Racing Marker
                Rectangle()
                    .fill(Color(hex: 0xE74C3C))
                    .frame(width: 8, height: size * 0.14)
                    .offset(y: -size / 2)

                // Interior Spokes
                Rectangle()
                    .fill(Color(white: 0.22))
                    .frame(width: size * 0.75, height: 16)

                Rectangle()
                    .fill(Color(white: 0.22))
                    .frame(width: 16, height: size * 0.40)
                    .offset(y: size * 0.18)

                // Center Boss / Horn Cap
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.25), Color(white: 0.10)],
                            center: .center,
                            startRadius: 5,
                            endRadius: size * 0.25
                        )
                    )
                    .frame(width: size * 0.40, height: size * 0.40)
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1.5))

                Image(systemName: "steeringwheel")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundColor(Color(hex: 0x00FFCC))

                // Angle Readout
                Text("\(Int(steeringAngle))°")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .offset(y: size * 0.12)
            }
            .rotationEffect(.degrees(steeringAngle))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: steeringAngle)
            .position(x: center.x, y: center.y)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isSteeringDragging = true
                        let translation = gesture.translation
                        // Map horizontal translation to angular deflection (-90° to +90°)
                        let maxDrag: CGFloat = size * 0.6
                        let clampedX = max(-maxDrag, min(maxDrag, translation.width))
                        let angle = Double(clampedX / maxDrag) * 90.0
                        self.steeringAngle = angle

                        // Report to ViewModel as normalized horizontal stick (-1.0 to 1.0)
                        let normalizedX = CGFloat(angle / 90.0)
                        controllerVM.updateLeftStick(x: normalizedX, y: 0)
                    }
                    .onEnded { _ in
                        isSteeringDragging = false
                        // Return steering wheel smoothly to center
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                            self.steeringAngle = 0.0
                        }
                        controllerVM.updateLeftStick(x: 0, y: 0)
                    }
            )
        }
        .frame(width: size, height: size)
    }

    // MARK: - Theme Color Helper

    private var themeColor: Color {
        switch settingsVM.selectedTheme {
        case .light:
            return Color.blue
        case .dark:
            return Color(hex: 0x2A75D3)
        case .neon:
            return Color(hex: 0x00FFCC)
        case .midnight:
            return Color(hex: 0x00E5FF)
        case .custom:
            return Color(hex: 0x5856D6)
        }
    }

    // MARK: - Device Orientation Control

    private func lockOrientation(to orientation: UIInterfaceOrientation) {
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private func restoreOrientation() {
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

#if DEBUG
struct ControllerView_Previews: PreviewProvider {
    static var previews: some View {
        ControllerView()
            .previewInterfaceOrientation(.landscapeRight)
            .preferredColorScheme(.dark)
    }
}
#endif
