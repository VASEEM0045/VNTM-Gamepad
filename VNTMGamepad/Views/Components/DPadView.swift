//
//  DPadView.swift
//  VNTM Gamepad
//
//  An 8-directional D-pad component with geometry-based touch zone resolution,
//  visual segment highlighting, classic directional arrows, and center release.
//

import SwiftUI

/// Represents the four physical cardinal arms of the D-pad cross.
public enum DPadArm {
    case up, down, left, right
}

/// A classic plus-shaped 8-directional D-pad view.
///
/// Features precision geometry-based direction resolution (cardinal + diagonal),
/// responsive arm lighting, tactile center pivot simulation, and .center reporting on release.
public struct DPadView: View {
    // MARK: - Properties

    let size: CGFloat
    let onDirectionChange: (DPadDirection) -> Void

    // MARK: - State

    @State private var currentDirection: DPadDirection = .center

    // MARK: - Dimensions

    private var armWidth: CGFloat { size * 0.34 }
    private var cornerRadius: CGFloat { 10 }
    private var centerThreshold: CGFloat { armWidth * 0.38 }

    // MARK: - Initialization

    /// Creates an 8-directional D-pad.
    /// - Parameters:
    ///   - size: Bounding square diameter of the D-pad cross. Defaults to 140.
    ///   - onDirectionChange: Callback triggered whenever the active direction changes.
    public init(
        size: CGFloat = 140,
        onDirectionChange: @escaping (DPadDirection) -> Void
    ) {
        self.size = size
        self.onDirectionChange = onDirectionChange
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                // Outer subtle chassis shadow
                crossShape
                    .fill(Color.black.opacity(0.5))
                    .blur(radius: 6)
                    .offset(y: 3)

                // Main Cross Chassis (Horizontal & Vertical Arms)
                crossShape
                    .fill(chassisGradient)

                // Arm Segment Highlighting
                armHighlights

                // Diagonal Corner Indicators
                diagonalHighlights

                // Cross Border / Bevel
                crossShape
                    .strokeBorder(crossBorderGradient, lineWidth: 1.5)

                // Directional Arrow Symbols
                directionalArrows

                // Central Pivot Dish
                centerPivot
            }
            .frame(width: size, height: size)
            .position(center)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        handleTouch(location: gesture.location, in: proxy.size)
                    }
                    .onEnded { _ in
                        handleRelease()
                    }
            )
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.16, dampingFraction: 0.7), value: currentDirection)
        // Accessibility
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Directional Pad"))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityValue(Text(accessibilityDirectionName))
    }

    // MARK: - Cross Shape

    private var crossShape: some InsettableShape {
        DPadCrossShape(size: size, armWidth: armWidth, cornerRadius: cornerRadius)
    }

    private var chassisGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(white: 0.22),
                Color(white: 0.15),
                Color(white: 0.11)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var crossBorderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.25),
                Color.white.opacity(0.08),
                Color.black.opacity(0.50)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Arm Highlights

    private var armHighlights: some View {
        ZStack {
            // Up Arm
            if isArmActive(.up) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(activeGlowGradient)
                    .frame(width: armWidth - 2, height: (size - armWidth) / 2 + 6)
                    .offset(y: -(size - armWidth) / 4)
            }

            // Down Arm
            if isArmActive(.down) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(activeGlowGradient)
                    .frame(width: armWidth - 2, height: (size - armWidth) / 2 + 6)
                    .offset(y: (size - armWidth) / 4)
            }

            // Left Arm
            if isArmActive(.left) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(activeGlowGradient)
                    .frame(width: (size - armWidth) / 2 + 6, height: armWidth - 2)
                    .offset(x: -(size - armWidth) / 4)
            }

            // Right Arm
            if isArmActive(.right) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(activeGlowGradient)
                    .frame(width: (size - armWidth) / 2 + 6, height: armWidth - 2)
                    .offset(x: (size - armWidth) / 4)
            }
        }
        .mask(crossShape)
    }

    private var activeGlowGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.cyan.opacity(0.55),
                Color.blue.opacity(0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Diagonal Corner Indicator Dots

    private var diagonalHighlights: some View {
        let cornerDist = size * 0.32
        return ZStack {
            cornerPip(direction: .upRight, x: cornerDist, y: -cornerDist)
            cornerPip(direction: .downRight, x: cornerDist, y: cornerDist)
            cornerPip(direction: .downLeft, x: -cornerDist, y: cornerDist)
            cornerPip(direction: .upLeft, x: -cornerDist, y: -cornerDist)
        }
    }

    @ViewBuilder
    private func cornerPip(direction: DPadDirection, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(currentDirection == direction ? Color.cyan : Color.white.opacity(0.08))
            .frame(width: 5, height: 5)
            .shadow(
                color: currentDirection == direction ? Color.cyan.opacity(0.8) : Color.clear,
                radius: 4
            )
            .offset(x: x, y: y)
    }

    // MARK: - Arrow Indicators

    private var directionalArrows: some View {
        let arrowOffset = size * 0.35
        return ZStack {
            // Up Arrow
            arrowImage("chevron.up", active: isArmActive(.up))
                .offset(y: -arrowOffset)

            // Down Arrow
            arrowImage("chevron.down", active: isArmActive(.down))
                .offset(y: arrowOffset)

            // Left Arrow
            arrowImage("chevron.left", active: isArmActive(.left))
                .offset(x: -arrowOffset)

            // Right Arrow
            arrowImage("chevron.right", active: isArmActive(.right))
                .offset(x: arrowOffset)
        }
    }

    private func arrowImage(_ systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: armWidth * 0.36, weight: .black))
            .foregroundColor(active ? .white : Color.white.opacity(0.40))
            .shadow(
                color: active ? Color.cyan.opacity(0.8) : Color.black.opacity(0.4),
                radius: active ? 4 : 1
            )
            .scaleEffect(active ? 1.15 : 1.0)
    }

    // MARK: - Center Pivot Dish

    private var centerPivot: some View {
        ZStack {
            // Recessed center circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.10),
                            Color(white: 0.18)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: armWidth * 0.36
                    )
                )
                .frame(width: armWidth * 0.72, height: armWidth * 0.72)

            // Bevel rim
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: armWidth * 0.72, height: armWidth * 0.72)

            // Center tactile pip
            Circle()
                .fill(Color.white.opacity(currentDirection == .center ? 0.25 : 0.10))
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Direction Resolution

    private func isArmActive(_ arm: DPadArm) -> Bool {
        switch arm {
        case .up:
            return currentDirection == .up || currentDirection == .upRight || currentDirection == .upLeft
        case .down:
            return currentDirection == .down || currentDirection == .downRight || currentDirection == .downLeft
        case .left:
            return currentDirection == .left || currentDirection == .upLeft || currentDirection == .downLeft
        case .right:
            return currentDirection == .right || currentDirection == .upRight || currentDirection == .downRight
        }
    }

    private func handleTouch(location: CGPoint, in bounds: CGSize) {
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)

        let newDirection: DPadDirection
        if distance < centerThreshold {
            newDirection = .center
        } else {
            // Angle in screen coordinates: 0 is Right, 90 is Down, 180 is Left, 270 is Up
            var degrees = Double(atan2(dy, dx)) * 180.0 / .pi
            if degrees < 0 { degrees += 360 }

            // 8 sectors of 45 degrees, centered on 0, 45, 90, 135, 180, 225, 270, 315
            let sector = Int((degrees + 22.5) / 45.0) % 8
            switch sector {
            case 0: newDirection = .right
            case 1: newDirection = .downRight
            case 2: newDirection = .down
            case 3: newDirection = .downLeft
            case 4: newDirection = .left
            case 5: newDirection = .upLeft
            case 6: newDirection = .up
            default: newDirection = .upRight
            }
        }

        if newDirection != currentDirection {
            currentDirection = newDirection
            onDirectionChange(newDirection)
        }
    }

    private func handleRelease() {
        if currentDirection != .center {
            currentDirection = .center
            onDirectionChange(.center)
        }
    }

    private var accessibilityDirectionName: String {
        switch currentDirection {
        case .center: return "Center (Neutral)"
        case .up: return "Up"
        case .upRight: return "Up-Right"
        case .right: return "Right"
        case .downRight: return "Down-Right"
        case .down: return "Down"
        case .downLeft: return "Down-Left"
        case .left: return "Left"
        case .upLeft: return "Up-Left"
        }
    }
}

// MARK: - DPad Cross Insettable Shape

struct DPadCrossShape: InsettableShape {
    let size: CGFloat
    let armWidth: CGFloat
    let cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> DPadCrossShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let actualSize = min(rect.width, rect.height) - insetAmount * 2
        let actualArmWidth = (armWidth / size) * actualSize
        let r = max(2, (cornerRadius / size) * actualSize)

        let minX = rect.midX - actualSize / 2
        let maxX = rect.midX + actualSize / 2
        let minY = rect.midY - actualSize / 2
        let maxY = rect.midY + actualSize / 2

        let armMinX = rect.midX - actualArmWidth / 2
        let armMaxX = rect.midX + actualArmWidth / 2
        let armMinY = rect.midY - actualArmWidth / 2
        let armMaxY = rect.midY + actualArmWidth / 2

        var path = Path()

        // Construct standard rounded cross path
        path.addPath(
            RoundedRectangle(cornerRadius: r)
                .path(in: CGRect(x: armMinX, y: minY, width: actualArmWidth, height: actualSize))
        )
        path.addPath(
            RoundedRectangle(cornerRadius: r)
                .path(in: CGRect(x: minX, y: armMinY, width: actualSize, height: actualArmWidth))
        )

        return path
    }
}

// MARK: - Previews

#if DEBUG
struct DPadView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var direction: DPadDirection = .center

        var body: some View {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()

                VStack(spacing: 30) {
                    Text("Direction: \(direction.rawValue)")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)

                    DPadView(size: 150) { newDir in
                        direction = newDir
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
