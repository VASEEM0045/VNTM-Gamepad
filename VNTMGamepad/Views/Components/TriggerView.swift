//
//  TriggerView.swift
//  VNTM Gamepad
//
//  An analog trigger component (LT/RT) featuring a progressive vertical fill bar,
//  dynamic accent gradients, smooth spring release, and percentage display.
//

import SwiftUI

/// An analog trigger component for left (LT) and right (RT) triggers.
///
/// Provides responsive vertical touch drag control, fill percentage indicator,
/// dynamic color graduation, and tactile spring release animation.
public struct TriggerView: View {
    // MARK: - Parameters

    let label: String
    let side: TriggerSide
    let width: CGFloat
    let height: CGFloat
    let onUpdate: (CGFloat) -> Void

    // MARK: - State

    @State private var value: CGFloat = 0.0
    @State private var isTouching: Bool = false

    // MARK: - Initialization

    /// Creates an analog trigger view.
    /// - Parameters:
    ///   - label: Display label (e.g. "LT", "RT").
    ///   - side: Side orientation (.left or .right).
    ///   - width: Width of the trigger bar. Defaults to 58.
    ///   - height: Height of the trigger bar. Defaults to 124.
    ///   - onUpdate: Callback providing normalized trigger travel in 0.0...1.0.
    public init(
        label: String,
        side: TriggerSide,
        width: CGFloat = 58,
        height: CGFloat = 124,
        onUpdate: @escaping (CGFloat) -> Void
    ) {
        self.label = label
        self.side = side
        self.width = width
        self.height = height
        self.onUpdate = onUpdate
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 6) {
            // Header: Label & Side symbol
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(headerColor)

                Image(systemName: side == .left ? "arrow.left.to.line" : "arrow.right.to.line")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(headerColor.opacity(0.8))
            }

            // Main Trigger Track & Fill
            ZStack(alignment: .bottom) {
                // Background Track
                trackBackground

                // Dynamic Fill Level Bar
                fillBar

                // Tick Marks & Ruler Overlay
                rulerOverlay

                // Percentage Badge (Floats at fill front or center)
                percentageOverlay
            }
            .frame(width: width, height: height)
            .clipShape(triggerShape)
            .overlay(
                triggerShape
                    .strokeBorder(borderGradient, lineWidth: 1.5)
            )
            .shadow(
                color: accentColor.opacity(Double(value) * 0.4),
                radius: 8 * value,
                x: 0,
                y: 2
            )
            .contentShape(triggerShape)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        handleDrag(location: gesture.location)
                    }
                    .onEnded { _ in
                        handleDragEnded()
                    }
            )
        }
        // Accessibility
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label) Trigger"))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityValue(Text("\(Int(value * 100)) percent"))
    }

    // MARK: - Shapes & Gradients

    private var triggerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var accentColor: Color {
        side == .left ? Color(hex: 0x00D2FF) : Color(hex: 0xFF5E62)
    }

    private var headerColor: Color {
        value > 0.05 ? accentColor : Color.secondary
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.35),
                Color.white.opacity(0.10),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Subviews

    private var trackBackground: some View {
        ZStack {
            // Dark recessed fill
            triggerShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.14),
                            Color(white: 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Inner shadow for physical cavity look
            triggerShape
                .stroke(Color.black.opacity(0.6), lineWidth: 3)
                .blur(radius: 2)
        }
    }

    private var fillBar: some View {
        GeometryReader { proxy in
            let fillHeight = proxy.size.height * value

            VStack {
                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor,
                                accentColor.opacity(0.75),
                                Color.gray.opacity(0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: fillHeight)
                    // Bright luminous edge at top of the fill
                    .overlay(
                        VStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.8))
                                .frame(height: 2)
                                .blur(radius: 0.5)
                            Spacer()
                        }
                        .opacity(value > 0.02 ? 1 : 0)
                    )
            }
        }
        .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.8), value: value)
    }

    private var rulerOverlay: some View {
        VStack(spacing: 0) {
            ForEach(1..<6) { tick in
                Spacer()
                HStack {
                    if side == .left {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: tick == 3 ? 10 : 5, height: 1)
                        Spacer()
                    } else {
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: tick == 3 ? 10 : 5, height: 1)
                    }
                }
                .padding(.horizontal, 4)
            }
            Spacer()
        }
    }

    private var percentageOverlay: some View {
        VStack {
            Spacer()

            Text("\(Int(value * 100))%")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(value > 0.4 ? .white : .white.opacity(0.7))
                .shadow(color: Color.black.opacity(0.8), radius: 2, x: 0, y: 1)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Drag Logic

    private func handleDrag(location: CGPoint) {
        if !isTouching {
            isTouching = true
        }

        // Pulling down from top: location.y in 0...height
        let rawProgress = location.y / height
        let clamped = rawProgress.clamped(to: 0...1)

        self.value = clamped
        self.onUpdate(clamped)
    }

    private func handleDragEnded() {
        isTouching = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
            value = 0.0
        }
        onUpdate(0.0)
    }
}

// MARK: - Previews

#if DEBUG
struct TriggerView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var leftValue: CGFloat = 0.35
        @State private var rightValue: CGFloat = 0.85

        var body: some View {
            ZStack {
                Color(white: 0.07).ignoresSafeArea()

                HStack(spacing: 40) {
                    TriggerView(label: "LT", side: .left) { val in
                        leftValue = val
                    }

                    TriggerView(label: "RT", side: .right) { val in
                        rightValue = val
                    }
                }
                .padding()
            }
        }
    }

    static var previews: some View {
        PreviewWrapper()
            .previewLayout(.sizeThatFits)
    }
}
#endif
