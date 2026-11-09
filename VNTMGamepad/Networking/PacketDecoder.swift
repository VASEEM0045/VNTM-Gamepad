//
//  PacketDecoder.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// Represents an unpacked wire packet, including metadata, payload, and validation status.
public struct DecodedPacket: Equatable, Sendable {
    /// Semantic packet type.
    public let type: PacketType

    /// Extracted (and decrypted, if applicable) binary payload.
    public let payload: Data

    /// Indicates whether the header magic, length, and CRC16 checksum are valid.
    public let isValid: Bool

    /// CRC16 checksum read from the packet trailer.
    public let checksum: UInt16

    /// CRC16 checksum recalculated over the received bytes.
    public let computedChecksum: UInt16

    /// Raw binary slice representing this packet in its entirety.
    public let rawData: Data

    public init(
        type: PacketType,
        payload: Data,
        isValid: Bool,
        checksum: UInt16,
        computedChecksum: UInt16,
        rawData: Data
    ) {
        self.type = type
        self.payload = payload
        self.isValid = isValid
        self.checksum = checksum
        self.computedChecksum = computedChecksum
        self.rawData = rawData
    }

    // MARK: - Parsed Type Accessors

    /// Unpacks and constructs a `ControllerState` if this packet is of type `.controllerState`.
    public var controllerState: ControllerState? {
        guard type == .controllerState, isValid else { return nil }
        return PacketDecoder.parseControllerState(from: payload)
    }

    /// Unpacks device name string if this packet is of type `.handshake`.
    public var handshakeDeviceName: String? {
        guard type == .handshake, isValid else { return nil }
        return PacketDecoder.parseHandshake(from: payload)
    }

    /// Unpacks monotonic timestamp if this packet is of type `.heartbeat`.
    public var heartbeatTimestamp: UInt64? {
        guard type == .heartbeat, isValid else { return nil }
        return PacketDecoder.parseHeartbeat(from: payload)
    }

    /// Unpacks acknowledgment sequence number if this packet is of type `.ack`.
    public var ackSequence: UInt16? {
        guard type == .ack, isValid else { return nil }
        return PacketDecoder.parseAck(from: payload)
    }
}

/// Static decoder responsible for un-framing binary packets, validating header magic
/// bytes (0x56 0x4E / "VN"), verifying CRC16 checksums, decrypting payloads, and
/// deserializing typed messages.
public struct PacketDecoder {

    private init() {}

    // MARK: - Primary Decoding

    /// Decodes a binary packet buffer into a `DecodedPacket`.
    ///
    /// Validates header magic bytes (`0x56, 0x4E`), confirms length bounds, calculates
    /// and checks the CRC16 trailer, and extracts the payload.
    ///
    /// - Parameter data: Raw data containing at least one full packet.
    /// - Returns: A `DecodedPacket` if the packet framing is intact, or `nil` if malformed.
    public static func decode(_ data: Data) -> DecodedPacket? {
        decode(data, key: nil)
    }

    /// Decodes a binary packet buffer with an optional AES-256 decryption key.
    ///
    /// If the packet is encrypted (or its payload is encrypted), the key will be used
    /// to decrypt the contents using CryptoKit AES-GCM or CommonCrypto AES-CBC.
    ///
    /// - Parameters:
    ///   - data: Raw received data.
    ///   - key: Optional 256-bit AES key.
    /// - Returns: A `DecodedPacket` if the packet can be parsed, or `nil` if malformed.
    public static func decode(_ data: Data, key: Data?) -> DecodedPacket? {
        var workingData = data

        // Minimum packet length: Header(2) + Type(1) + Length(2) + Checksum(2) = 7 bytes
        guard workingData.count >= PacketEncoder.framingOverhead else {
            return nil
        }

        let initialBytes = [UInt8](workingData)

        // Validate header magic bytes (0xVN = 0x56, 0x4E). Also accept 0x56, 0x47 ("VG") as legacy alias.
        let magicValid = initialBytes[0] == PacketEncoder.headerMagic0 &&
                         (initialBytes[1] == PacketEncoder.headerMagic1 || initialBytes[1] == 0x47)

        // If magic bytes do not match and a key is provided, the entire packet may be encrypted
        if !magicValid {
            if let key = key, let decryptedEntirePacket = decrypt(workingData, key: key) {
                workingData = decryptedEntirePacket
                guard workingData.count >= PacketEncoder.framingOverhead else { return nil }
                let decBytes = [UInt8](workingData)
                guard decBytes[0] == PacketEncoder.headerMagic0 &&
                      (decBytes[1] == PacketEncoder.headerMagic1 || decBytes[1] == 0x47) else {
                    return nil
                }
            } else {
                return nil
            }
        }

        let currentBytes = [UInt8](workingData)

        // Parse packet type
        guard let packetType = PacketType(rawValue: currentBytes[2]) else {
            return nil
        }

        // Parse declared payload length (Big Endian UInt16)
        let payloadLength = (Int(currentBytes[3]) << 8) | Int(currentBytes[4])
        let totalExpectedLength = PacketEncoder.framingOverhead + payloadLength

        // Guard against truncated data
        guard workingData.count >= totalExpectedLength else {
            return nil
        }

        // Extract payload
        let payloadStart = 5
        let payloadEnd = payloadStart + payloadLength
        var extractedPayload = workingData.subdata(in: payloadStart..<payloadEnd)

        // Extract transmitted checksum (Big Endian UInt16)
        let checksumStart = payloadEnd
        let transmittedChecksum = (UInt16(currentBytes[checksumStart]) << 8) | UInt16(currentBytes[checksumStart + 1])

        // Recalculate checksum over Header + Type + Length + Payload
        let bytesCovered = workingData.subdata(in: 0..<checksumStart)
        let computedChecksum = PacketEncoder.crc16(bytesCovered)
        let isChecksumValid = (computedChecksum == transmittedChecksum)

        // Decrypt payload if encryption key is supplied and payload is non-empty
        if let key = key, !extractedPayload.isEmpty {
            if let decryptedPayload = decrypt(extractedPayload, key: key) {
                extractedPayload = decryptedPayload
            }
        }

        let packetSlice = workingData.prefix(totalExpectedLength)

        return DecodedPacket(
            type: packetType,
            payload: extractedPayload,
            isValid: isChecksumValid,
            checksum: transmittedChecksum,
            computedChecksum: computedChecksum,
            rawData: packetSlice
        )
    }

    // MARK: - Streaming Decoder

    /// Parses all complete packets from a mutable data stream buffer, removing processed
    /// bytes from the input buffer and returning an array of decoded packets.
    ///
    /// Handles stream fragmentation, prepended noise, and partial packets.
    ///
    /// - Parameters:
    ///   - buffer: Inout streaming buffer accumulating received chunks.
    ///   - key: Optional decryption key.
    /// - Returns: Array of parsed `DecodedPacket`s.
    public static func decodeStream(from buffer: inout Data, key: Data? = nil) -> [DecodedPacket] {
        var packets: [DecodedPacket] = []

        while buffer.count >= PacketEncoder.framingOverhead {
            // Find magic header 'V'
            guard let magicIndex = buffer.firstIndex(of: PacketEncoder.headerMagic0) else {
                buffer.removeAll()
                break
            }

            // Discard any garbage before the magic header
            if magicIndex > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<magicIndex)
            }

            guard buffer.count >= PacketEncoder.framingOverhead else { break }

            let byte1 = buffer[buffer.index(buffer.startIndex, offsetBy: 1)]
            guard byte1 == PacketEncoder.headerMagic1 || byte1 == 0x47 else {
                // False magic0 byte; discard it and keep searching
                buffer.removeFirst()
                continue
            }

            // Read payload length
            let lenByte0 = buffer[buffer.index(buffer.startIndex, offsetBy: 3)]
            let lenByte1 = buffer[buffer.index(buffer.startIndex, offsetBy: 4)]
            let payloadLength = (Int(lenByte0) << 8) | Int(lenByte1)
            let totalLength = PacketEncoder.framingOverhead + payloadLength

            // Wait for full packet if not yet complete in buffer
            guard buffer.count >= totalLength else {
                break
            }

            let packetData = buffer.prefix(totalLength)
            if let packet = decode(packetData, key: key) {
                packets.append(packet)
            }

            buffer.removeSubrange(buffer.startIndex..<buffer.index(buffer.startIndex, offsetBy: totalLength))
        }

        return packets
    }

    // MARK: - Specialized Parsers

    /// Parses a binary payload into a `ControllerState`.
    /// Supports both standard 19-byte payloads (with DPadDirection byte) and 18-byte legacy formats.
    ///
    /// - Parameter payload: The binary payload slice.
    /// - Returns: A populated `ControllerState`, or `nil` if malformed.
    public static func parseControllerState(from payload: Data) -> ControllerState? {
        if let state = ControllerState(data: payload) {
            return state
        }

        guard payload.count >= 18 else { return nil }
        let bytes = [UInt8](payload)

        let buttons = UInt32(bigEndianBytes: bytes, offset: 0)
        let lx = bytes[4]
        let ly = bytes[5]
        let rx = bytes[6]
        let ry = bytes[7]
        let lt = bytes[8]
        let rt = bytes[9]

        let dpad: DPadDirection
        let timestamp: UInt64

        if payload.count >= 19 {
            dpad = DPadDirection(byteValue: bytes[10])
            timestamp = UInt64(bigEndianBytes: bytes, offset: 11)
        } else {
            dpad = .center
            timestamp = UInt64(bigEndianBytes: bytes, offset: 10)
        }

        return ControllerState(
            buttons: buttons,
            leftStickX: lx,
            leftStickY: ly,
            rightStickX: rx,
            rightStickY: ry,
            leftTrigger: lt,
            rightTrigger: rt,
            dpadState: dpad,
            timestamp: timestamp
        )
    }

    /// Parses a UTF-8 encoded device name from a `.handshake` payload.
    ///
    /// - Parameter payload: The handshake binary payload.
    /// - Returns: Device name string, or `nil` if empty/invalid UTF-8.
    public static func parseHandshake(from payload: Data) -> String? {
        guard !payload.isEmpty else { return nil }
        return String(data: payload, encoding: .utf8)
    }

    /// Parses an 8-byte big-endian monotonic timestamp from a `.heartbeat` payload.
    ///
    /// - Parameter payload: The heartbeat binary payload.
    /// - Returns: Monotonic timestamp in milliseconds, or `nil` if payload is truncated.
    public static func parseHeartbeat(from payload: Data) -> UInt64? {
        guard payload.count >= 8 else { return nil }
        let bytes = [UInt8](payload)
        return UInt64(bigEndianBytes: bytes, offset: 0)
    }

    /// Parses a 2-byte big-endian sequence number from an `.ack` payload.
    ///
    /// - Parameter payload: The acknowledgment binary payload.
    /// - Returns: Acknowledgment sequence number, or `nil` if truncated.
    public static func parseAck(from payload: Data) -> UInt16? {
        guard payload.count >= 2 else { return nil }
        let bytes = [UInt8](payload)
        return UInt16(bigEndianBytes: bytes, offset: 0)
    }

    // MARK: - AES-256 Decryption

    /// Decrypts ciphertext using AES-256.
    /// Attempts CryptoKit AES-GCM first, falling back to CommonCrypto AES-CBC.
    ///
    /// - Parameters:
    ///   - data: Encrypted ciphertext data.
    ///   - key: Encryption key. A 32-byte key is used directly; otherwise SHA-256 is derived.
    /// - Returns: Plaintext data if decryption succeeds, or `nil` on failure.
    public static func decrypt(_ data: Data, key: Data) -> Data? {
        #if canImport(CryptoKit)
        if #available(iOS 13.0, macOS 10.15, *) {
            do {
                let symmetricKey: SymmetricKey
                if key.count == 32 {
                    symmetricKey = SymmetricKey(data: key)
                } else {
                    let hash = SHA256.hash(data: key)
                    symmetricKey = SymmetricKey(data: Data(hash))
                }
                let sealedBox = try AES.GCM.SealedBox(combined: data)
                let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)
                return decrypted
            } catch {
                // If CryptoKit GCM fails, fall through to CommonCrypto fallback
            }
        }
        #endif

        #if canImport(CommonCrypto)
        return commonCryptoDecrypt(data, key: key)
        #else
        return nil
        #endif
    }

    #if canImport(CommonCrypto)
    /// CommonCrypto fallback decryptor using AES-256-CBC with PKCS7 padding.
    /// Expects the first 16 bytes to be the initialization vector (IV).
    private static func commonCryptoDecrypt(_ data: Data, key: Data) -> Data? {
        guard data.count > kCCBlockSizeAES128 else { return nil }

        let keyLength = kCCKeySizeAES256
        var keyBytes = [UInt8](repeating: 0, count: keyLength)

        if key.count == keyLength {
            key.copyBytes(to: &keyBytes, count: keyLength)
        } else {
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            key.withUnsafeBytes { rawBuffer in
                _ = CC_SHA256(rawBuffer.baseAddress, CC_LONG(key.count), &digest)
            }
            keyBytes = digest
        }

        let iv = [UInt8](data.prefix(kCCBlockSizeAES128))
        let ciphertext = [UInt8](data.dropFirst(kCCBlockSizeAES128))

        let bufferSize = ciphertext.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var numBytesDecrypted: size_t = 0

        let cryptStatus = keyBytes.withUnsafeBytes { keyBuf in
            ciphertext.withUnsafeBytes { cipherBuf in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    keyBuf.baseAddress,
                    keyLength,
                    iv,
                    cipherBuf.baseAddress,
                    ciphertext.count,
                    &buffer,
                    bufferSize,
                    &numBytesDecrypted
                )
            }
        }

        guard cryptStatus == kCCSuccess else { return nil }
        return Data(buffer.prefix(numBytesDecrypted))
    }
    #endif
}
