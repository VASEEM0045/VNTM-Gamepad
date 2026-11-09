//
//  VNTMGamepadTests.swift
//  VNTMGamepadTests
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//

import XCTest
@testable import VNTMGamepad

final class VNTMGamepadTests: XCTestCase {

    // MARK: - ControllerState: Button Bitmask Operations

    func testControllerStateButtonPressReleaseBitmask() {
        var state = ControllerState()

        // 1. Initial state has zero buttons active
        XCTAssertEqual(state.buttons, 0)
        XCTAssertFalse(state.isButtonPressed(.a))
        XCTAssertFalse(state.isButtonPressed(.b))
        XCTAssertFalse(state.isButtonPressed(.x))
        XCTAssertFalse(state.isButtonPressed(.y))

        // 2. Press button A
        state.pressButton(.a)
        XCTAssertTrue(state.isButtonPressed(.a))
        XCTAssertEqual(state.buttons & ButtonMask.a.rawValue, ButtonMask.a.rawValue)
        XCTAssertEqual(state.buttons, 1)

        // 3. Press button B while holding A
        state.pressButton(.b)
        XCTAssertTrue(state.isButtonPressed(.a))
        XCTAssertTrue(state.isButtonPressed(.b))
        XCTAssertEqual(state.buttons, ButtonMask.a.rawValue | ButtonMask.b.rawValue)

        // 4. Release button A, B remains pressed
        state.releaseButton(.a)
        XCTAssertFalse(state.isButtonPressed(.a))
        XCTAssertTrue(state.isButtonPressed(.b))
        XCTAssertEqual(state.buttons, ButtonMask.b.rawValue)

        // 5. Test setButtonPressed helper
        state.setButtonPressed(.x, isPressed: true)
        XCTAssertTrue(state.isButtonPressed(.x))
        state.setButtonPressed(.x, isPressed: false)
        XCTAssertFalse(state.isButtonPressed(.x))

        // 6. Test all button bits independently
        for button in ButtonMask.allCases {
            var singleState = ControllerState()
            singleState.pressButton(button)
            XCTAssertTrue(singleState.isButtonPressed(button))
            XCTAssertEqual(singleState.buttons, button.rawValue)

            singleState.releaseButton(button)
            XCTAssertFalse(singleState.isButtonPressed(button))
            XCTAssertEqual(singleState.buttons, 0)
        }

        // 7. Reset to neutral clears all buttons
        state.pressButton(.a)
        state.pressButton(.rb)
        state.pressButton(.start)
        XCTAssertNotEqual(state.buttons, 0)
        state.resetToNeutral()
        XCTAssertEqual(state.buttons, 0)
        XCTAssertFalse(state.isButtonPressed(.a))
        XCTAssertFalse(state.isButtonPressed(.rb))
        XCTAssertFalse(state.isButtonPressed(.start))
    }

    // MARK: - ControllerState: toData() Serialization

    func testControllerStateToDataSerialization() {
        // 1. Neutral state byte count
        let neutralState = ControllerState.neutral()
        let neutralData = neutralState.toData()
        XCTAssertEqual(neutralData.count, 19, "ControllerState wire serialization must produce exactly 19 bytes")

        // 2. State with specific input values
        var state = ControllerState()
        state.pressButton(.a)
        state.pressButton(.rb)
        state.leftStickX = 200
        state.leftStickY = 64
        state.rightStickX = 180
        state.rightStickY = 120
        state.leftTrigger = 255
        state.rightTrigger = 128
        state.dpadState = .upRight
        state.timestamp = 987654321

        let data = state.toData()
        XCTAssertEqual(data.count, 19)

        // 3. Verify wire structure byte-by-byte
        let bytes = [UInt8](data)
        // Buttons UInt32 (big-endian)
        let expectedButtons = ButtonMask.a.rawValue | ButtonMask.rb.rawValue
        let parsedButtons = UInt32(bigEndianBytes: bytes, offset: 0)
        XCTAssertEqual(parsedButtons, expectedButtons)

        // Analog axes
        XCTAssertEqual(bytes[4], 200) // leftStickX
        XCTAssertEqual(bytes[5], 64)  // leftStickY
        XCTAssertEqual(bytes[6], 180) // rightStickX
        XCTAssertEqual(bytes[7], 120) // rightStickY
        XCTAssertEqual(bytes[8], 255) // leftTrigger
        XCTAssertEqual(bytes[9], 128) // rightTrigger
        XCTAssertEqual(bytes[10], DPadDirection.upRight.byteValue) // dpadState

        // Timestamp UInt64 (big-endian)
        let parsedTimestamp = UInt64(bigEndianBytes: bytes, offset: 11)
        XCTAssertEqual(parsedTimestamp, 987654321)

        // 4. Deserialization roundtrip via ControllerState(data:)
        let restored = ControllerState(data: data)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.buttons, expectedButtons)
        XCTAssertTrue(restored?.isButtonPressed(.a) == true)
        XCTAssertTrue(restored?.isButtonPressed(.rb) == true)
        XCTAssertFalse(restored?.isButtonPressed(.b) == true)
        XCTAssertEqual(restored?.leftStickX, 200)
        XCTAssertEqual(restored?.leftStickY, 64)
        XCTAssertEqual(restored?.rightStickX, 180)
        XCTAssertEqual(restored?.rightStickY, 120)
        XCTAssertEqual(restored?.leftTrigger, 255)
        XCTAssertEqual(restored?.rightTrigger, 128)
        XCTAssertEqual(restored?.dpadState, .upRight)
        XCTAssertEqual(restored?.timestamp, 987654321)

        // 5. Payload convenience accessor matches toData()
        XCTAssertEqual(state.payload, state.toData())
    }

    // MARK: - PacketEncoder: Header Magic Bytes

    func testPacketEncoderHeaderMagicBytes() {
        XCTAssertEqual(PacketEncoder.headerMagic0, 0x56, "Magic byte 0 must be 'V' (0x56)")
        XCTAssertEqual(PacketEncoder.headerMagic1, 0x4E, "Magic byte 1 must be 'N' (0x4E)")
        XCTAssertEqual(PacketEncoder.magicHeader, [0x56, 0x4E])

        let state = ControllerState.neutral()
        let packet = PacketEncoder.encode(state)

        // Verify packet header
        XCTAssertGreaterThanOrEqual(packet.count, PacketEncoder.framingOverhead)
        XCTAssertEqual(packet[0], PacketEncoder.headerMagic0)
        XCTAssertEqual(packet[1], PacketEncoder.headerMagic1)
        XCTAssertEqual(packet[2], PacketType.controllerState.rawValue)

        // Verify length field in packet header (Big Endian UInt16 = 19)
        let payloadLength = (UInt16(packet[3]) << 8) | UInt16(packet[4])
        XCTAssertEqual(payloadLength, 19)
        XCTAssertEqual(packet.count, PacketEncoder.framingOverhead + 19)
    }

    // MARK: - PacketEncoder: Heartbeat Packet Structure

    func testPacketEncoderHeartbeatPacketStructure() {
        let testTimestamp: UInt64 = 1715000000123
        let heartbeatPacket = PacketEncoder.encodeHeartbeat(timestamp: testTimestamp)

        // Frame: Header (2) + Type (1) + Length (2) + Payload (8) + Checksum (2) = 15 bytes
        let expectedTotalLength = PacketEncoder.framingOverhead + 8
        XCTAssertEqual(heartbeatPacket.count, expectedTotalLength)

        // Header magic bytes: 'V', 'N'
        XCTAssertEqual(heartbeatPacket[0], PacketEncoder.headerMagic0)
        XCTAssertEqual(heartbeatPacket[1], PacketEncoder.headerMagic1)

        // Packet type: heartbeat (0x02)
        XCTAssertEqual(heartbeatPacket[2], PacketType.heartbeat.rawValue)

        // Declared payload length: 8 bytes
        let length = (UInt16(heartbeatPacket[3]) << 8) | UInt16(heartbeatPacket[4])
        XCTAssertEqual(length, 8)

        // Timestamp payload matches big-endian encoded timestamp
        let payloadBytes = [UInt8](heartbeatPacket.subdata(in: 5..<13))
        let extractedTimestamp = UInt64(bigEndianBytes: payloadBytes, offset: 0)
        XCTAssertEqual(extractedTimestamp, testTimestamp)

        // Decoded via PacketDecoder
        let decoded = PacketDecoder.decode(heartbeatPacket)
        XCTAssertNotNil(decoded)
        XCTAssertTrue(decoded!.isValid)
        XCTAssertEqual(decoded!.type, .heartbeat)
        XCTAssertEqual(decoded!.heartbeatTimestamp, testTimestamp)
    }

    // MARK: - PacketDecoder: Roundtrip Decoding

    func testPacketDecoderRoundtrip() {
        var originalState = ControllerState()
        originalState.pressButton(.y)
        originalState.pressButton(.lb)
        originalState.leftStickX = 42
        originalState.leftStickY = 220
        originalState.rightStickX = 128
        originalState.rightStickY = 250
        originalState.leftTrigger = 75
        originalState.rightTrigger = 200
        originalState.dpadState = .downLeft
        originalState.timestamp = 1122334455

        // Encode state into wire format
        let encodedData = PacketEncoder.encode(originalState)

        // Decode packet from wire format
        let decodedPacket = PacketDecoder.decode(encodedData)
        XCTAssertNotNil(decodedPacket)
        XCTAssertTrue(decodedPacket!.isValid)
        XCTAssertEqual(decodedPacket!.type, .controllerState)
        XCTAssertEqual(decodedPacket!.checksum, decodedPacket!.computedChecksum)

        // Restore ControllerState from packet payload
        let restoredState = decodedPacket!.controllerState
        XCTAssertNotNil(restoredState)
        XCTAssertTrue(restoredState!.isButtonPressed(.y))
        XCTAssertTrue(restoredState!.isButtonPressed(.lb))
        XCTAssertFalse(restoredState!.isButtonPressed(.a))
        XCTAssertFalse(restoredState!.isButtonPressed(.x))
        XCTAssertEqual(restoredState!.leftStickX, 42)
        XCTAssertEqual(restoredState!.leftStickY, 220)
        XCTAssertEqual(restoredState!.rightStickX, 128)
        XCTAssertEqual(restoredState!.rightStickY, 250)
        XCTAssertEqual(restoredState!.leftTrigger, 75)
        XCTAssertEqual(restoredState!.rightTrigger, 200)
        XCTAssertEqual(restoredState!.dpadState, .downLeft)
        XCTAssertEqual(restoredState!.timestamp, 1122334455)
    }

    // MARK: - PacketDecoder: Invalid Header Rejection

    func testPacketDecoderInvalidHeaderRejection() {
        let validState = ControllerState.neutral()
        let validPacket = PacketEncoder.encode(validState)

        // 1. Corrupt magic header bytes
        var invalidHeaderPacket = validPacket
        invalidHeaderPacket[0] = 0x00
        invalidHeaderPacket[1] = 0x00
        XCTAssertNil(PacketDecoder.decode(invalidHeaderPacket), "Decoder must reject packets with invalid magic header")

        // 2. Corrupted checksum trailer
        var badChecksumPacket = validPacket
        let lastIdx = badChecksumPacket.count - 1
        badChecksumPacket[lastIdx] ^= 0xFF
        let decodedBadChecksum = PacketDecoder.decode(badChecksumPacket)
        XCTAssertNotNil(decodedBadChecksum)
        XCTAssertFalse(decodedBadChecksum!.isValid, "Decoder must flag checksum mismatch")

        // 3. Truncated packet below framing overhead
        let truncatedPacket = validPacket.prefix(5)
        XCTAssertNil(PacketDecoder.decode(truncatedPacket), "Decoder must reject truncated packets")

        // 4. Declared length larger than available data
        var lengthExceededPacket = validPacket
        lengthExceededPacket[3] = 0xFF // 65280 bytes length
        lengthExceededPacket[4] = 0x00
        XCTAssertNil(PacketDecoder.decode(lengthExceededPacket), "Decoder must reject packet with length exceeding data buffer")
    }

    // MARK: - ControllerProfile: Default Values

    func testControllerProfileDefaultValues() {
        let profile = ControllerProfile.default

        // Identity & Layout
        XCTAssertEqual(profile.name, "Default Profile")
        XCTAssertEqual(profile.layout, .classic)
        XCTAssertTrue(profile.buttonMapping.isEmpty)
        XCTAssertEqual(profile.hapticIntensity, 1.0)
        XCTAssertEqual(profile.overlayOpacity, 0.8)
        XCTAssertEqual(profile.theme, .dark)

        // Sensitivity Defaults
        XCTAssertEqual(profile.sensitivity.leftStickSensitivity, 1.0)
        XCTAssertEqual(profile.sensitivity.rightStickSensitivity, 1.0)
        XCTAssertEqual(profile.sensitivity.leftTriggerSensitivity, 1.0)
        XCTAssertEqual(profile.sensitivity.rightTriggerSensitivity, 1.0)
        XCTAssertEqual(profile.sensitivity.motionSensitivity, 1.0)

        // Dead Zone Defaults
        XCTAssertEqual(profile.deadZones.leftStickDeadZone, 0.08)
        XCTAssertEqual(profile.deadZones.rightStickDeadZone, 0.08)
        XCTAssertEqual(profile.deadZones.leftTriggerDeadZone, 0.05)
        XCTAssertEqual(profile.deadZones.rightTriggerDeadZone, 0.05)

        // Factory Presets
        let classicProfile = ControllerProfile.classic()
        XCTAssertEqual(classicProfile.layout, .classic)
        XCTAssertEqual(classicProfile.name, "Classic")

        let arcadeProfile = ControllerProfile.arcade()
        XCTAssertEqual(arcadeProfile.layout, .arcade)
        XCTAssertEqual(arcadeProfile.name, "Arcade")

        let racingProfile = ControllerProfile.racing()
        XCTAssertEqual(racingProfile.layout, .racing)
        XCTAssertEqual(racingProfile.name, "Racing")
    }

    // MARK: - DeadZone: Values Within Dead Zone Map to Center

    func testDeadZoneMapsToCenter() {
        // 1. Analog stick within dead zone maps to (0, 0)
        let deadZone = 0.10
        let smallDeflection = CGPoint(x: 0.04, y: 0.03) // magnitude = 0.05 < deadZone 0.10
        let normalizedStick = InputMapping.normalizeStick(
            smallDeflection,
            deadZone: deadZone,
            sensitivity: 1.0,
            curve: .linear
        )
        XCTAssertEqual(normalizedStick.x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(normalizedStick.y, 0.0, accuracy: 0.0001)

        // 2. Wire stick byte at center is 128
        let byteX = InputMapping.stickByte(from: Double(normalizedStick.x))
        let byteY = InputMapping.stickByte(from: Double(normalizedStick.y))
        XCTAssertEqual(byteX, ControllerState.stickCenter, "Stick at center deadzone must serialize to 128")
        XCTAssertEqual(byteY, ControllerState.stickCenter, "Stick at center deadzone must serialize to 128")

        // 3. Stick exactly at resting origin
        let restingStick = InputMapping.normalizeStick(
            .zero,
            deadZone: 0.08,
            sensitivity: 1.0,
            curve: .linear
        )
        XCTAssertEqual(restingStick, .zero)

        // 4. shapeMagnitude helper returns 0 within dead zone
        let shapedInner = InputMapping.shapeMagnitude(0.05, deadZone: 0.08, sensitivity: 1.0, curve: .linear)
        XCTAssertEqual(shapedInner, 0.0)

        // 5. shapeMagnitude helper scales properly outside dead zone
        let shapedOuter = InputMapping.shapeMagnitude(0.54, deadZone: 0.08, sensitivity: 1.0, curve: .linear)
        XCTAssertGreaterThan(shapedOuter, 0.0)

        // 6. Trigger dead zone maps to 0.0
        let restingTrigger = InputMapping.normalizeTrigger(0.03, deadZone: 0.05, sensitivity: 1.0, curve: .linear)
        XCTAssertEqual(restingTrigger, 0.0)

        // 7. D-Pad center deadzone returns no active buttons
        let centerDpadButtons = DPadResolver.buttons(for: CGPoint(x: 0.05, y: 0.05), deadZone: 0.25)
        XCTAssertTrue(centerDpadButtons.isEmpty, "Deflections within D-pad deadzone must resolve to empty set")

        // 8. DeadZoneSettings clamping guarantees valid range 0.0 ... 0.5
        XCTAssertEqual(DeadZoneSettings.clamp(-0.1), 0.0)
        XCTAssertEqual(DeadZoneSettings.clamp(0.6), 0.5)
        XCTAssertEqual(DeadZoneSettings.clamp(0.25), 0.25)
    }

    // MARK: - Sensitivity: Curve Application

    func testSensitivityCurveApplication() {
        // 1. Boundary invariance: All response curves pin 0.0 and 1.0
        for curve in ResponseCurve.allCases {
            XCTAssertEqual(curve.apply(0.0), 0.0, accuracy: 0.0001, "Curve \(curve) must pin 0.0")
            XCTAssertEqual(curve.apply(1.0), 1.0, accuracy: 0.0001, "Curve \(curve) must pin 1.0")
        }

        // 2. Linear curve has 1:1 response
        XCTAssertEqual(ResponseCurve.linear.apply(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ResponseCurve.linear.apply(0.25), 0.25, accuracy: 0.0001)

        // 3. Quadratic (precision) curve provides finer control near origin (x^2)
        XCTAssertEqual(ResponseCurve.quadratic.apply(0.5), 0.25, accuracy: 0.0001)
        XCTAssertEqual(ResponseCurve.quadratic.apply(0.2), 0.04, accuracy: 0.0001)

        // 4. Sigmoid (S-Curve) smoothstep response
        // f(0.5) = 0.5^2 * (3.0 - 2.0 * 0.5) = 0.25 * 2.0 = 0.5
        XCTAssertEqual(ResponseCurve.sigmoid.apply(0.5), 0.5, accuracy: 0.0001)

        // 5. Exponential response curve is monotonic
        let expQuarter = ResponseCurve.exponential.apply(0.25)
        let expHalf = ResponseCurve.exponential.apply(0.5)
        let expThreeQuarters = ResponseCurve.exponential.apply(0.75)
        XCTAssertLessThan(expQuarter, expHalf)
        XCTAssertLessThan(expHalf, expThreeQuarters)

        // 6. InputMapping sensitivity scaling
        // With sensitivity = 1.0, deadZone = 0.0, linear curve
        let normalMapped = InputMapping.shapeMagnitude(0.4, deadZone: 0.0, sensitivity: 1.0, curve: .linear)
        XCTAssertEqual(normalMapped, 0.4, accuracy: 0.001)

        // With sensitivity = 1.5
        let boostedMapped = InputMapping.shapeMagnitude(0.4, deadZone: 0.0, sensitivity: 1.5, curve: .linear)
        XCTAssertEqual(boostedMapped, 0.6, accuracy: 0.001)

        // Sensitivity saturation clamps at 1.0
        let saturatedMapped = InputMapping.shapeMagnitude(0.9, deadZone: 0.0, sensitivity: 2.0, curve: .linear)
        XCTAssertEqual(saturatedMapped, 1.0, accuracy: 0.001)
    }

    // MARK: - Legacy Unit Tests

    func testAppConstants() {
        XCTAssertEqual(AppConstants.appName, "VNTM Gamepad")
        XCTAssertEqual(AppConstants.bundleId, "com.vntm.gamepad")
        XCTAssertEqual(AppConstants.WiFi.defaultPort, 7777)
        XCTAssertEqual(AppConstants.Protocol.headerMagic, [0x56, 0x4E])
    }

    func testNormalizedByteConversion() {
        XCTAssertEqual(UInt8(fromNormalized: 0.0), 0)
        XCTAssertEqual(UInt8(fromNormalized: 0.5), 128)
        XCTAssertEqual(UInt8(fromNormalized: 1.0), 255)
        XCTAssertEqual(UInt8(fromNormalized: -1.0), 0)
        XCTAssertEqual(UInt8(fromNormalized: 2.0), 255)
    }

    func testDataHexString() {
        let data = Data([0x56, 0x4E, 0x01, 0xFF])
        XCTAssertEqual(data.hexString, "56 4E 01 FF")
        XCTAssertEqual(Data(hexString: "564E01FF"), data)
        XCTAssertEqual(Data(hexString: "56 4E 01 FF"), data)
    }

    func testClamping() {
        let valDouble: Double = 1.5
        XCTAssertEqual(valDouble.clamped(to: 0.0...1.0), 1.0)

        let valCGFloat: CGFloat = -0.5
        XCTAssertEqual(valCGFloat.clamped(to: 0.0...1.0), 0.0)
    }
}
