//
//  VirtualButton.swift
//  VNTM Gamepad
//
//  A reusable, high-performance game controller button component designed for
//  responsive multi-touch gameplay.
//

import SwiftUI

/// A reusable digital controller button designed for virtual gamepads.
///
/// Supports multi-touch interactions without gesture interference, realistic
/// physical feedback styling (scale, shadow, gradient, inner shadow), and accessibility.
public struct VirtualButton: View {
    // MARK: - Properties

    let label: String
    let buttonColor: Color
    let size: CGFloat
    @Binding var isPressed: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    // MARK: - Initialization

    /// Creates a virtual gamepad button.
    /// - Parameters:
    ///   - label: The display label on the button face (e.g. "A", "B", "X", "Y").
    ///   - buttonColor: Base accent color for the button.
    ///   - size: Diameter of the button circle in points. Defaults to 60.
    ///   - isPressed: Binding reflecting the physical touch state.
    ///   - onPress: Closure invoked on initial finger contact.
    ///   - onRelease: Closure invoked when the touch lifts or is cancelled.
    public init(
        label: String,
        buttonColor: Color,
        size: CGFloat = 60,
        isPressed: Binding<Bool>,
        onPress: @escaping () -> Void = {},
        onRelease: @escaping () -> Void = {}
    ) {
        self.label = label
        self.buttonColor = buttonColor
        self.size = size
        self._isPressed = isPressed
        self.onPress = onPress
        self.onRelease = onRelease
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Base circular button with gradient fill
            Circle()
                .fill(buttonGradient)
                .frame(width: size, height: size)

            // Inner dark shading when pressed
            if isPressed {
                Circle()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: size, height: size)

                // Realistic inner shadow simulation
                Circle()
                    .stroke(Color.black.opacity(0.65), lineWidth: max(2, size * 0.05))
                    .blur(radius: max(1.5, size * 0.035))
                    .offset(x: 0, y: max(1, size * 0.025))
                    .mask(Circle().frame(width: size, height: size))
            }

            // Subtle top highlight border for depth
            Circle()
                .strokeBorder(highlightGradient, lineWidth: max(1, size * 0.025))
                .frame(width: size, height: size)

            // Button label text
            Text(label)
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(
                    color: Color.black.opacity(isPressed ? 0.6 : 0.35),
                    radius: isPressed ? 1 : 2,
                    x: 0,
                    y: isPressed ? 0.5 : 1
                )
        }
        // Outer shadow when unpressed; reduced when pressed
        .shadow(
            color: isPressed ? buttonColor.opacity(0.15) : buttonColor.opacity(0.45),
            radius: isPressed ? 2 : 6,
            x: 0,
            y: isPressed ? 1 : 3
        )
        .scaleEffect(isPressed ? 0.90 : 1.0)
        .animation(.spring(response: 0.18, dampingFraction: 0.65), value: isPressed)
        // Multi-touch friendly drag gesture
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onPress()
                    }
                }
                .onEnded { _ in
                    if isPressed {
                        isPressed = false
                        onRelease()
                    }
                }
        )
        // Accessibility
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label) Button"))
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(isPressed ? "Pressed" : "Released"))
    }

    // MARK: - Gradients

    private var buttonGradient: LinearGradient {
        if isPressed {
            return LinearGradient(
                colors: [
                    buttonColor.opacity(0.85),
                    buttonColor.opacity(0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    buttonColor.opacity(0.95),
                    buttonColor.opacity(0.75)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var highlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isPressed ? 0.20 : 0.50),
                Color.white.opacity(0.05),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Previews

#if DEBUG
struct VirtualButton_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var aPressed = false
        @State private var bPressed = true
        @State private var xPressed = false
        @State private var yPressed = false

        var body: some View {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                HStack(spacing: 20) {
                    VirtualButton(
                        label: "X",
                        buttonColor: Color(hex: 0x2A75D3),
                        size: 64,
                        isPressed: $xPressed
                    )
                    VirtualButton(
                        label: "Y",
                        buttonColor: Color(hex: 0xF5B324),
                        size: 64,
                        isPressed: $yPressed
                    )
                    VirtualButton(
                        label: "A",
                        buttonColor: Color(hex: 0x2ECC71),
                        size: 64,
                        isPressed: $aPressed
                    )
                    VirtualButton(
                        label: "B",
                        buttonColor: Color(hex: 0xE74C3C),
                        size: 64,
                        isPressed: $bPressed
                    )
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
