//
//  InputMapping.swift
//  VNTM Gamepad
//
//  Pure functions that translate raw touch values into wire values.
//  Everything here is deliberately free of SwiftUI and hardware so it can be
//  unit tested directly.
//

import Foundation

enum InputMapping {

    /// Applies the dead zone, sensitivity and response curve to a single
    /// magnitude in 0...1. Radial (not per-axis) dead zones keep circular
    /// motion feeling correct on analog sticks.
    static func shapeMagnitude(_ magnitude: Double,
                               deadZone: Double,
                               sensitivity: Double,
                               curve: ResponseCurve) -> Double {
        let clampedMagnitude = magnitude.clamped01
        let zone = deadZone.clamped(to: 0...0.5)
        guard clampedMagnitude > zone else { return 0 }

        // Rescale the remaining range so the stick still reaches 1.0.
        let scaled = (clampedMagnitude - zone) / (1.0 - zone)
        let curved = curve.apply(scaled)
        return (curved * sensitivity.clamped(to: 0.2...2.0)).clamped01
    }

    /// Normalises a raw stick deflection (-1...1 on each axis) and returns
    /// the corrected vector. `trim` compensates for a stick that does not
    /// rest exactly at the origin.
    static func normalizeStick(_ raw: CGPoint,
                               deadZone: Double,
                               sensitivity: Double,
                               curve: ResponseCurve,
                               trim: CGPoint = .zero,
                               invertY: Bool = false) -> CGPoint {
        var dx = raw.x - trim.x
        var dy = raw.y - trim.y

        // Keep the vector inside the unit circle before shaping it.
        let point = CGPoint(x: dx, y: dy).clamped(toRadius: 1.0)
        dx = point.x
        dy = point.y

        let magnitude = point.magnitude
        guard magnitude > 0 else { return .zero }

        let shaped = shapeMagnitude(Double(magnitude),
                                    deadZone: deadZone,
                                    sensitivity: sensitivity,
                                    curve: curve)
        guard shaped > 0 else { return .zero }

        let scale = CGFloat(shaped / Double(magnitude))
        var result = CGPoint(x: dx * scale, y: dy * scale)
        if invertY { result.y = -result.y }
        return result
    }

    /// Maps a trigger squeeze (0...1) through the dead zone and curve.
    static func normalizeTrigger(_ raw: Double,
                                 deadZone: Double,
                                 sensitivity: Double,
                                 curve: ResponseCurve) -> Double {
        shapeMagnitude(raw.clamped01,
                       deadZone: deadZone,
                       sensitivity: sensitivity,
                       curve: curve)
    }

    /// -1...1 -> 0...255 with 0 landing at 128.
    static func stickByte(from value: Double) -> UInt8 {
        let clamped = value.clamped(to: -1...1)
        return UInt8(((clamped + 1.0) / 2.0 * 255.0).rounded())
    }

    /// 0...1 -> 0...255
    static func triggerByte(from value: Double) -> UInt8 {
        value.asControllerByte
    }

    /// Byte -> -1...1 (used by the calibration screen to display trim).
    static func stickUnit(from byte: UInt8) -> Double {
        byte.unitValue * 2.0 - 1.0
    }
}

// MARK: - D-Pad geometry

enum DPadResolver {
    /// Turns a vector into the set of D-pad bits that should be held.
    /// Returns an empty set in the centre dead zone.
    static func buttons(for offset: CGPoint, deadZone: CGFloat = 0.25) -> Set<ControllerButton> {
        let magnitude = offset.magnitude
        guard magnitude > deadZone else { return [] }

        // 8 sectors of 45 degrees. Screen coordinates: +y is down.
        var degrees = Double(offset.angle) * 180.0 / .pi
        if degrees < 0 { degrees += 360 }

        let sector = Int((degrees + 22.5) / 45.0) % 8
        switch sector {
        case 0: return [.dpadRight]
        case 1: return [.dpadRight, .dpadDown]
        case 2: return [.dpadDown]
        case 3: return [.dpadLeft, .dpadDown]
        case 4: return [.dpadLeft]
        case 5: return [.dpadLeft, .dpadUp]
        case 6: return [.dpadUp]
        default: return [.dpadRight, .dpadUp]
        }
    }
}
