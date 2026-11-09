//
//  Extensions.swift
//  VNTM Gamepad
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Clamping

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }

    var clamped01: Double { clamped(to: 0...1) }

    /// Maps a 0...1 value onto a 0...255 byte.
    var asControllerByte: UInt8 {
        UInt8((clamped01 * 255.0).rounded())
    }

    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(self, range.lowerBound), range.upperBound)
    }

    var clamped01: CGFloat { clamped(to: 0...1) }
}

extension Float {
    var clamped01: Float { min(max(self, 0), 1) }
}

// MARK: - Geometry

extension CGPoint {
    var magnitude: CGFloat { sqrt(x * x + y * y) }

    var angle: CGFloat { atan2(y, x) }

    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    /// Constrains the point to a circle centred on the origin.
    func clamped(toRadius radius: CGFloat) -> CGPoint {
        let length = magnitude
        guard length > radius, length > 0 else { return self }
        let scale = radius / length
        return CGPoint(x: x * scale, y: y * scale)
    }

    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}

// MARK: - Colours

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    init(hexString: String, fallback: Color = .gray) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let hex = UInt32(value, radix: 16) else {
            self = fallback
            return
        }
        self.init(hex: hex)
    }

    // Static gamepad colors
    static let primaryButton = Color(hex: 0x2A2E3D)
    static let secondaryButton = Color(hex: 0x1E222D)
    static let accentGreen = Color(hex: 0x2ECC71)
    static let accentRed = Color(hex: 0xE74C3C)
    static let accentBlue = Color(hex: 0x3498DB)
    static let accentYellow = Color(hex: 0xF1C40F)
    static let background = Color(hex: 0x0D0F14)
    static let surface = Color(hex: 0x161A23)
}

// MARK: - Data

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var hexStringCompact: String {
        map { String(format: "%02X", $0) }.joined()
    }

    init?(hexString: String) {
        let cleaned = hexString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")
        guard cleaned.count % 2 == 0 else { return nil }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}

// MARK: - Bytes

extension UInt8 {
    /// Converts a normalized value in 0...1 to 0...255.
    init(fromNormalized value: CGFloat) {
        let clamped = value.clamped(to: 0.0...1.0)
        self = UInt8((clamped * 255.0).rounded())
    }

    /// 0...255 -> 0...1
    var unitValue: Double { Double(self) / 255.0 }
}

extension UInt16 {
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }

    init(bigEndianBytes bytes: [UInt8], offset: Int = 0) {
        self = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
}

extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 24) & 0xFF),
         UInt8((self >> 16) & 0xFF),
         UInt8((self >> 8) & 0xFF),
         UInt8(self & 0xFF)]
    }

    init(bigEndianBytes bytes: [UInt8], offset: Int = 0) {
        self = UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }
}

extension UInt64 {
    var bigEndianBytes: [UInt8] {
        (0..<8).map { UInt8((self >> (56 - UInt64($0) * 8)) & 0xFF) }
    }

    init(bigEndianBytes bytes: [UInt8], offset: Int = 0) {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = value << 8 | UInt64(bytes[offset + index])
        }
        self = value
    }
}

// MARK: - Time

extension Date {
    var millisecondsSinceEpoch: UInt64 {
        UInt64(timeIntervalSince1970 * 1_000.0)
    }

    /// Monotonic clock in milliseconds. Used inside packets so the
    /// companion can order and time-stamp inputs without clock sync.
    static var monotonicMilliseconds: UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }
}

extension DispatchTimeInterval {
    var timeInterval: TimeInterval {
        switch self {
        case .seconds(let value): return TimeInterval(value)
        case .milliseconds(let value): return TimeInterval(value) / 1_000.0
        case .microseconds(let value): return TimeInterval(value) / 1_000_000.0
        case .nanoseconds(let value): return TimeInterval(value) / 1_000_000_000.0
        case .never: return .infinity
        @unknown default: return 0
        }
    }
}

// MARK: - Shapes & Views

#if canImport(UIKit)
struct RoundedCornerShape: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
#endif

extension View {
    #if canImport(UIKit)
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }

    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif

    func panelStyle(cornerRadius: CGFloat = UIConstants.panelCornerRadius) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool,
                             transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func hidden(_ isHidden: Bool) -> some View {
        opacity(isHidden ? 0 : 1)
            .allowsHitTesting(!isHidden)
            .accessibilityHidden(isHidden)
    }
}
