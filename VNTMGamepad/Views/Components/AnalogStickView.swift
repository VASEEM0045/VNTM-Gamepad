//
//  AnalogStickView.swift
//  VNTM Gamepad
//
//  A virtual analog thumbstick component supporting dead-zones, directional crosshairs,
//  circular boundary clamping, and real-time position reporting.
//

import SwiftUI

/// A virtual analog thumbstick view with precision dead-zone filtering,
/// realistic physical resistance feedback, and crosshair visual guides.
public struct AnalogStickView: View {
    // MARK: - Parameters

    let size: CGFloat
    let deadZone: CGFloat
    let onUpdate: (CGFloat, CGFloat) -> Void

    // MARK: - State

    @State private var thumbOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    // MARK: - Constants & Derived Values

    private var trackRadius: CGFloat { size / 2 }
    private var thumbSize: CGFloat { size * 0.42 }
    private var maxTravelRadius: CGFloat { (size - thumbSize) / 2 }

    // MARK: - Initialization

    /// Creates an analog stick view.
    /// - Parameters:
    ///   - size: Diameter of the outer stick track. Defaults to 150.
    ///   - deadZone: Normalized dead-zone threshold (0...1). Defaults to 0.1.
    ///   - onUpdate: Callback providing normalized (x, y) coordinates in range -1.0...1.0 (where Up is +1, Right is +1).
    public init(
        size: CGFloat = 150,
        deadZone: CGFloat = 0.1,
        onUpdate: @escaping (CGFloat, CGFloat) -> Void
    ) {
        self.size = size
        self.deadZone = deadZone
        self.onUpdate = onUpdate
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // MARK: Track Background
            trackBackground

            // MARK: Crosshair Guides
            crosshairGuides

            // MARK: Deadzone & Range Ring Guides
            rangeGuideCircles

            // MARK: Vector Line Indicator
            if isDragging && currentMagnitude > deadZone {
                activeVectorLine
            }

            // MARK: Thumbstick
            thumbView
                .offset(thumbOffset)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    handleDrag(translation: gesture.translation)
                }
                .onEnded { _ in
                    handleDragEnded()
                }
        )
        // Accessibility
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Analog Stick"))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityValue(Text(accessibilityPositionText))
    }

    // MARK: - Subviews

    private var trackBackground: some View {
        ZStack {
            // Dark recessed dish
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.12),
                            Color(white: 0.06),
                            Color(white: 0.02)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: trackRadius
                    )
                )

            // Outer rim ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            Color.white.opacity(0.04),
                            Color.black.opacity(0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )

            // Inner recess shadow
            Circle()
                .stroke(Color.black.opacity(0.70), lineWidth: 5)
                .blur(radius: 4)
                .mask(Circle())
        }
    }

    private var crosshairGuides: some View {
        ZStack {
            // Horizontal guide
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: size * 0.85, height: 1)

            // Vertical guide
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: size * 0.85)

            // Cardinal tick marks
            ForEach([0, 90, 180, 270], id: \.self) { degrees in
                Rectangle()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 2, height: 6)
                    .offset(y: -trackRadius + 6)
                    .rotationEffect(.degrees(Double(degrees)))
            }
        }
    }

    private var rangeGuideCircles: some View {
        ZStack {
            // Deadzone indicator circle
            Circle()
                .stroke(
                    Color.white.opacity(0.10),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                .frame(
                    width: maxTravelRadius * deadZone * 2,
                    height: maxTravelRadius * deadZone * 2
                )

            // 50% radius guide
            Circle()
                .stroke(
                    Color.white.opacity(0.06),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .frame(
                    width: maxTravelRadius * 2,
                    height: maxTravelRadius * 2
                )
        }
    }

    private var activeVectorLine: some View {
        Path { path in
            path.move(to: CGPoint(x: trackRadius, y: trackRadius))
            path.addLine(to: CGPoint(
                x: trackRadius + thumbOffset.width,
                y: trackRadius + thumbOffset.height
            ))
        }
        .stroke(
            LinearGradient(
                colors: [Color.cyan.opacity(0.2), Color.cyan.opacity(0.8)],
                startPoint: .center,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
    }

    private var thumbView: some View {
        ZStack {
            // Outer thumb drop shadow
            Circle()
                .fill(Color.black.opacity(0.45))
                .frame(width: thumbSize, height: thumbSize)
                .blur(radius: isDragging ? 6 : 4)
                .offset(y: isDragging ? 3 : 2)

            // Thumb base body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.32),
                            Color(white: 0.20),
                            Color(white: 0.14)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: thumbSize / 2
                    )
                )
                .frame(width: thumbSize, height: thumbSize)

            // Textured grip concentric ridges
            Circle()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: thumbSize * 0.76, height: thumbSize * 0.76)

            Circle()
                .strokeBorder(Color.black.opacity(0.4), lineWidth: 1)
                .frame(width: thumbSize * 0.60, height: thumbSize * 0.60)

            // Inner concave center
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.12),
                            Color(white: 0.22)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: thumbSize * 0.25
                    )
                )
                .frame(width: thumbSize * 0.44, height: thumbSize * 0.44)

            // Center position indicator pip
            Circle()
                .fill(isDragging && currentMagnitude > deadZone ? Color.cyan : Color.white.opacity(0.35))
                .frame(width: 6, height: 6)
                .shadow(
                    color: isDragging && currentMagnitude > deadZone ? Color.cyan.opacity(0.8) : Color.clear,
                    radius: 4
                )

            // Directional notch marks on thumb perimeter
            ForEach([0, 90, 180, 270], id: \.self) { deg in
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 3, height: 3)
                    .offset(y: -(thumbSize * 0.38))
                    .rotationEffect(.degrees(Double(deg)))
            }

            // Top rim highlight
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
                .frame(width: thumbSize, height: thumbSize)
        }
        .scaleEffect(isDragging ? 1.04 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
    }

    // MARK: - Drag Logic & Math

    private var currentMagnitude: CGFloat {
        let dist = hypot(thumbOffset.width, thumbOffset.height)
        return maxTravelRadius > 0 ? (dist / maxTravelRadius) : 0
    }

    private func handleDrag(translation: CGSize) {
        if !isDragging {
            isDragging = true
        }

        let dx = translation.width
        let dy = translation.height
        let rawDistance = hypot(dx, dy)

        // Angle from origin
        let angle = atan2(dy, dx)

        // Clamp thumb position to physical circle travel radius
        let clampedDistance = min(rawDistance, maxTravelRadius)
        let clampedX = clampedDistance * cos(angle)
        let clampedY = clampedDistance * sin(angle)

        self.thumbOffset = CGSize(width: clampedX, height: clampedY)

        // Calculate normalized magnitude (0...1)
        let normMagnitude = maxTravelRadius > 0 ? (clampedDistance / maxTravelRadius) : 0

        // Apply dead zone
        if normMagnitude < deadZone {
            onUpdate(0, 0)
        } else {
            // Re-scale remaining travel smoothly to 0...1 range
            let usableRange = max(1.0 - deadZone, 0.001)
            let scaledMagnitude = (normMagnitude - deadZone) / usableRange

            // Normalized X in -1...1 (Right is positive)
            let normalizedX = (cos(angle) * scaledMagnitude).clamped(to: -1.0...1.0)
            // Normalized Y in -1...1 (Up is positive in standard controller space)
            let normalizedY = (-sin(angle) * scaledMagnitude).clamped(to: -1.0...1.0)

            onUpdate(normalizedX, normalizedY)
        }
    }

    private func handleDragEnded() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) {
            thumbOffset = .zero
            isDragging = false
        }
        onUpdate(0, 0)
    }

    private var accessibilityPositionText: String {
        if !isDragging || currentMagnitude < deadZone {
            return "Centered"
        }
        let normX = thumbOffset.width / maxTravelRadius
        let normY = -thumbOffset.height / maxTravelRadius
        return String(format: "X: %.1f, Y: %.1f", normX, normY)
    }
}

// MARK: - Previews

#if DEBUG
struct AnalogStickView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var stickX: CGFloat = 0
        @State private var stickY: CGFloat = 0

        var body: some View {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()

                VStack(spacing: 24) {
                    Text(String(format: "X: %+.2f  |  Y: %+.2f", stickX, stickY))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)

                    AnalogStickView(size: 160, deadZone: 0.12) { x, y in
                        stickX = x
                        stickY = y
                    }
                }
            }
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
#endif
