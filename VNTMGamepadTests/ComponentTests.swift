//
//  ComponentTests.swift
//  VNTMGamepadTests
//
//  Unit tests covering core math, direction mapping, and status classifications
//  used by the SwiftUI gamepad components.
//

import XCTest
import SwiftUI
@testable import VNTMGamepad

final class ComponentTests: XCTestCase {

    // MARK: - DPadDirection Tests

    func testDPadDirectionCases() {
        let expectedCases: [DPadDirection] = [
            .up, .upRight, .right, .downRight,
            .down, .downLeft, .left, .upLeft, .center
        ]

        for dir in expectedCases {
            XCTAssertFalse(dir.rawValue.isEmpty)
        }
        XCTAssertEqual(DPadDirection.center, DPadDirection.none)
    }

    func testControllerStateDPadSetting() {
        var state = ControllerState()
        XCTAssertEqual(state.dpadDirection, .center)

        state.setDPad(.up)
        XCTAssertEqual(state.dpadDirection, .up)
        XCTAssertTrue(state.isPressed(.dpadUp))
        XCTAssertFalse(state.isPressed(.dpadDown))

        state.setDPad(.upRight)
        XCTAssertEqual(state.dpadDirection, .upRight)
        XCTAssertTrue(state.isPressed(.dpadUp))
        XCTAssertTrue(state.isPressed(.dpadRight))

        state.setDPad(.center)
        XCTAssertEqual(state.dpadDirection, .center)
        XCTAssertFalse(state.isPressed(.dpadUp))
        XCTAssertFalse(state.isPressed(.dpadRight))
    }

    // MARK: - Analog Stick Clamping & Deadzone Tests

    func testStickDeadzoneThreshold() {
        let deadZone: CGFloat = 0.1
        let maxTravel: CGFloat = 50.0

        // Sub-deadzone offset
        let smallOffset = CGSize(width: 3.0, height: 3.0)
        let smallDist = hypot(smallOffset.width, smallOffset.height)
        let normMag = smallDist / maxTravel
        XCTAssertLessThan(normMag, deadZone)

        // Beyond deadzone offset
        let largeOffset = CGSize(width: 25.0, height: 25.0)
        let largeDist = hypot(largeOffset.width, largeOffset.height)
        let largeNormMag = largeDist / maxTravel
        XCTAssertGreaterThan(largeNormMag, deadZone)
    }

    // MARK: - Trigger Clamping Tests

    func testTriggerClamping() {
        let negativeVal: CGFloat = -0.2
        let normalVal: CGFloat = 0.75
        let overVal: CGFloat = 1.3

        XCTAssertEqual(negativeVal.clamped(to: 0...1), 0.0)
        XCTAssertEqual(normalVal.clamped(to: 0...1), 0.75)
        XCTAssertEqual(overVal.clamped(to: 0...1), 1.0)
    }

    // MARK: - Connection Latency Thresholds

    func testConnectionStatusColors() {
        XCTAssertEqual(ConnectionStatus.connected.themeColor, Color(hex: 0x2ECC71))
        XCTAssertEqual(ConnectionStatus.connecting.themeColor, Color(hex: 0xF1C40F))
        XCTAssertEqual(ConnectionStatus.disconnected.themeColor, Color(hex: 0x95A5A6))
        XCTAssertEqual(ConnectionStatus.error.themeColor, Color(hex: 0xE74C3C))
    }

    // MARK: - Input Visualizer State Integration

    func testInputVisualizerStateMapping() {
        var state = ControllerState()
        state.setPressed(.a, true)
        state.setPressed(.lb, true)
        state.leftTrigger = 255
        state.rightTrigger = 128
        state.leftStickX = 255 // +1.0
        state.leftStickY = 0   // -1.0 in raw byte, but inverted in controller space

        XCTAssertTrue(state.isPressed(.a))
        XCTAssertTrue(state.isPressed(.lb))
        XCTAssertFalse(state.isPressed(.b))
        XCTAssertEqual(state.leftTrigger, 255)
        XCTAssertEqual(state.rightTrigger, 128)
    }
}
