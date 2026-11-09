//
//  InputVisualizerView.swift
//  VNTM Gamepad
//
//  A comprehensive real-time input visualizer HUD for controller diagnostics,
//  calibration testing, and latency-free input inspection.
//

import SwiftUI

/// A read-only real-time diagnostic dashboard visualizing the complete
/// controller hardware state (sticks, triggers, D-pad, and digital buttons).
public struct InputVisualizerView: View {
    // MARK: - Properties

    let state: ControllerState

    // MARK: - Initialization

    /// Creates an input visualizer from a ControllerState snapshot.
    /// - Parameter state: The controller input state snapshot.
    public init(state: ControllerState = .neutral()) {
        self.state = state
    }

    /// Convenience initializer allowing individual normalized parameters.
    public init(
        buttons: UInt32 = 0,
        leftStick: CGPoint = .zero,
        rightStick: CGPoint = .zero,
        leftTrigger: CGFloat = 0.0,
        rightTrigger: CGFloat = 0.0,
        dpadDirection: DPadDirection = .center
    ) {
        var s = ControllerState(buttons: buttons)
        s.leftStickX = InputMapping.stickByte(from: Double(leftStick.x))
        s.leftStickY = InputMapping.stickByte(from: Double(-leftStick.y))
        s.rightStickX = InputMapping.stickByte(from: Double(rightStick.x))
        s.rightStickY = InputMapping.stickByte(from: Double(-rightStick.y))
        s.leftTrigger = InputMapping.triggerByte(from: Double(leftTrigger))
        s.rightTrigger = InputMapping.triggerByte(from: Double(rightTrigger))
        s.setDPad(dpadDirection)
        self.state = s
    }

    // MARK: - Normalized Properties

    private var leftStickNorm: CGPoint {
        CGPoint(
            x: CGFloat(InputMapping.stickUnit(from: state.leftStickX)),
            y: CGFloat(-InputMapping.stickUnit(from: state.leftStickY)) // Up is positive
        )
    }

    private var rightStickNorm: CGPoint {
        CGPoint(
            x: CGFloat(InputMapping.stickUnit(from: state.rightStickX)),
            y: CGFloat(-InputMapping.stickUnit(from: state.rightStickY)) // Up is positive
        )
    }

    private var leftTriggerNorm: CGFloat {
        CGFloat(Double(state.leftTrigger) / 255.0)
    }

    private var rightTriggerNorm: CGFloat {
        CGFloat(Double(state.rightTrigger) / 255.0)
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 14) {
            // MARK: Top Section - Triggers & Bumpers
            HStack(alignment: .top, spacing: 16) {
                // Left Trigger & Bumper
                VStack(alignment: .leading, spacing: 6) {
                    triggerBar(label: "LT", value: leftTriggerNorm, color: Color(hex: 0x00D2FF))
                    bumperIndicator(label: "LB", isPressed: state.isPressed(.lb))
                }

                Spacer()

                // Center System Buttons
                systemButtonsRow

                Spacer()

                // Right Trigger & Bumper
                VStack(alignment: .trailing, spacing: 6) {
                    triggerBar(label: "RT", value: rightTriggerNorm, color: Color(hex: 0xFF5E62))
                    bumperIndicator(label: "RB", isPressed: state.isPressed(.rb))
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // MARK: Middle & Bottom Section - Sticks, D-Pad, Face Buttons
            HStack(alignment: .center, spacing: 18) {
                // Left Stick Indicator
                stickIndicator(
                    label: "LEFT STICK",
                    normPos: leftStickNorm,
                    accentColor: Color.cyan
                )

                Spacer(minLength: 4)

                // D-Pad Directional Compass
                dpadIndicator

                Spacer(minLength: 4)

                // Face Buttons Diamond Grid
                faceButtonsDiamond

                Spacer(minLength: 4)

                // Right Stick Indicator
                stickIndicator(
                    label: "RIGHT STICK",
                    normPos: rightStickNorm,
                    accentColor: Color.purple
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.panelCornerRadius, style: .continuous)
                .fill(Color(white: 0.10).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.panelCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
        .allowsHitTesting(false) // Pure read-only display
        .animation(.spring(response: 0.15, dampingFraction: 0.75), value: state.buttons)
        .animation(.interactiveSpring(), value: state.leftStickX)
        .animation(.interactiveSpring(), value: state.rightStickX)
        .animation(.interactiveSpring(), value: state.leftTrigger)
        .animation(.interactiveSpring(), value: state.rightTrigger)
        // Accessibility
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Input Visualizer"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    // MARK: - Subviews: Triggers & Bumpers

    @ViewBuilder
    private func triggerBar(label: String, value: CGFloat, color: Color) -> some View {
        VStack(alignment: label == "LT" ? .leading : .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(value > 0.05 ? color : .secondary)

                Text("\(Int(value * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }

            // Fill Bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 80, height: 8)

                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(80, 80 * value)), height: 8)
                    .shadow(color: color.opacity(Double(value) * 0.6), radius: 3)
            }
        }
    }

    @ViewBuilder
    private func bumperIndicator(label: String, isPressed: Bool) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(isPressed ? .white : Color.white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isPressed ? Color.cyan.opacity(0.7) : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .stroke(isPressed ? Color.cyan : Color.white.opacity(0.15), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 1.05 : 1.0)
    }

    // MARK: - Subviews: System Buttons

    private var systemButtonsRow: some View {
        HStack(spacing: 12) {
            systemButton(name: "SELECT", symbol: "square.fill.and.line.vertical.and.square", isPressed: state.isPressed(.select))
            systemButton(name: "HOME", symbol: "house.fill", isPressed: state.isPressed(.home))
            systemButton(name: "START", symbol: "line.3.horizontal", isPressed: state.isPressed(.start))
        }
    }

    @ViewBuilder
    private func systemButton(name: String, symbol: String, isPressed: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isPressed ? .white : Color.white.opacity(0.45))
                .frame(width: 26, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isPressed ? Color.white.opacity(0.4) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isPressed ? Color.white : Color.white.opacity(0.15), lineWidth: 1)
                )

            Text(name)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(isPressed ? .white : .secondary)
        }
        .scaleEffect(isPressed ? 1.08 : 1.0)
    }

    // MARK: - Subviews: Stick Indicators

    @ViewBuilder
    private func stickIndicator(label: String, normPos: CGPoint, accentColor: Color) -> some View {
        let dialDiameter: CGFloat = 60
        let radius: CGFloat = dialDiameter / 2
        let dotRadius: CGFloat = 5
        let travelRadius: CGFloat = radius - dotRadius - 2

        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.secondary)

            ZStack {
                // Outer ring
                Circle()
                    .fill(Color(white: 0.06))
                    .frame(width: dialDiameter, height: dialDiameter)

                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .frame(width: dialDiameter, height: dialDiameter)

                // Crosshairs
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: dialDiameter * 0.8, height: 1)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1, height: dialDiameter * 0.8)

                // Deadzone reference circle
                Circle()
                    .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: dialDiameter * 0.35, height: dialDiameter * 0.35)

                // Stick thumb position dot
                let dotX = normPos.x * travelRadius
                let dotY = -normPos.y * travelRadius // Invert Y back to view space

                Circle()
                    .fill(accentColor)
                    .frame(width: dotRadius * 2, height: dotRadius * 2)
                    .shadow(color: accentColor.opacity(0.8), radius: 4)
                    .offset(x: dotX, y: dotY)
            }

            // Coordinates Readout
            Text(String(format: "%+.2f, %+.2f", normPos.x, normPos.y))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
        }
    }

    // MARK: - Subviews: D-Pad Indicator

    private var dpadIndicator: some View {
        let dir = state.dpadDirection
        let size: CGFloat = 64
        let armW: CGFloat = 20

        return VStack(spacing: 5) {
            Text("D-PAD")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.secondary)

            ZStack {
                // Cross background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: armW, height: size)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: size, height: armW)

                // Center intersection
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: armW, height: armW)

                // Up arrow
                Image(systemName: "triangle.fill")
                    .font(.system(size: 7))
                    .foregroundColor(isDPadUpActive(dir) ? .cyan : Color.white.opacity(0.25))
                    .offset(y: -size / 2 + 7)

                // Down arrow
                Image(systemName: "triangle.fill")
                    .font(.system(size: 7))
                    .rotationEffect(.degrees(180))
                    .foregroundColor(isDPadDownActive(dir) ? .cyan : Color.white.opacity(0.25))
                    .offset(y: size / 2 - 7)

                // Left arrow
                Image(systemName: "triangle.fill")
                    .font(.system(size: 7))
                    .rotationEffect(.degrees(270))
                    .foregroundColor(isDPadLeftActive(dir) ? .cyan : Color.white.opacity(0.25))
                    .offset(x: -size / 2 + 7)

                // Right arrow
                Image(systemName: "triangle.fill")
                    .font(.system(size: 7))
                    .rotationEffect(.degrees(90))
                    .foregroundColor(isDPadRightActive(dir) ? .cyan : Color.white.opacity(0.25))
                    .offset(x: size / 2 - 7)

                // Center pip
                Circle()
                    .fill(dir == .center ? Color.white.opacity(0.3) : Color.cyan)
                    .frame(width: 5, height: 5)
            }
            .frame(width: size, height: size)

            Text(dir == .center ? "CENTER" : dir.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(dir == .center ? .secondary : .cyan)
        }
    }

    private func isDPadUpActive(_ d: DPadDirection) -> Bool {
        d == .up || d == .upRight || d == .upLeft
    }

    private func isDPadDownActive(_ d: DPadDirection) -> Bool {
        d == .down || d == .downRight || d == .downLeft
    }

    private func isDPadLeftActive(_ d: DPadDirection) -> Bool {
        d == .left || d == .upLeft || d == .downLeft
    }

    private func isDPadRightActive(_ d: DPadDirection) -> Bool {
        d == .right || d == .upRight || d == .downRight
    }

    // MARK: - Subviews: Face Buttons Diamond Grid

    private var faceButtonsDiamond: some View {
        let btnSize: CGFloat = 22
        let spacing: CGFloat = 4

        return VStack(spacing: 5) {
            Text("BUTTONS")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.secondary)

            VStack(spacing: spacing) {
                // Top: Y
                faceButton(button: .y, color: Color(hex: 0xF5B324), size: btnSize)

                // Middle row: X and B
                HStack(spacing: spacing * 3) {
                    faceButton(button: .x, color: Color(hex: 0x2A75D3), size: btnSize)
                    faceButton(button: .b, color: Color(hex: 0xE74C3C), size: btnSize)
                }

                // Bottom: A
                faceButton(button: .a, color: Color(hex: 0x2ECC71), size: btnSize)
            }
            .frame(width: 64, height: 60)

            // Pressed count badge
            Text("\(state.pressedButtons.count) ACTIVE")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(state.pressedButtons.isEmpty ? .secondary : .green)
        }
    }

    @ViewBuilder
    private func faceButton(button: ControllerButton, color: Color, size: CGFloat) -> some View {
        let isPressed = state.isPressed(button)

        Circle()
            .fill(isPressed ? color : Color.white.opacity(0.10))
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(isPressed ? Color.white : color.opacity(0.4), lineWidth: 1)
            )
            .overlay(
                Text(button.displayName)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(isPressed ? .white : Color.white.opacity(0.7))
            )
            .shadow(color: isPressed ? color.opacity(0.8) : Color.clear, radius: 4)
            .scaleEffect(isPressed ? 1.15 : 1.0)
    }

    // MARK: - Accessibility

    private var accessibilitySummary: String {
        var items: [String] = []
        if state.leftTrigger > 0 { items.append("LT \(Int(leftTriggerNorm * 100))%") }
        if state.rightTrigger > 0 { items.append("RT \(Int(rightTriggerNorm * 100))%") }
        let pressed = state.pressedButtons.map { $0.displayName }
        if !pressed.isEmpty { items.append("Pressed: \(pressed.joined(separator: ", "))") }
        if state.dpadDirection != .center { items.append("D-pad: \(state.dpadDirection.rawValue)") }
        return items.isEmpty ? "All inputs idle" : items.joined(separator: "; ")
    }
}

// MARK: - Previews

#if DEBUG
struct InputVisualizerView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            VStack(spacing: 20) {
                // Neutral state
                InputVisualizerView(state: .neutral())

                // Active sample state
                let sampleState: ControllerState = {
                    var s = ControllerState()
                    s.setPressed(.a, true)
                    s.setPressed(.rb, true)
                    s.setDPad(.upRight)
                    s.leftStickX = 180
                    s.leftStickY = 60
                    s.rightStickX = 100
                    s.rightStickY = 210
                    s.leftTrigger = 180
                    s.rightTrigger = 90
                    return s
                }()

                InputVisualizerView(state: sampleState)
            }
            .padding()
        }
    }
}
#endif
