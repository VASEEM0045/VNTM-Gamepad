//
//  PacketEncoder.swift
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

/// Identifier representing the semantic type of a binary wire packet.
public enum PacketType: UInt8, CaseIterable, Codable, Sendable {
    case controllerState = 0x01
    case heartbeat       = 0x02
    case config          = 0x03
    case handshake       = 0x04
    case disconnect      = 0x05
    case ack             = 0x06

    /// Human-readable label for debugging and logging.
    public var displayName: String {
        switch self {
        case .controllerState: return "Controller State"
        case .heartbeat:       return "Heartbeat"
        case .config:          return "Config"
        case .handshake:       return "Handshake"
        case .disconnect:      return "Disconnect"
        case .ack:             return "Acknowledgement"
        }
    }
}

/// Static encoder responsible for packaging controller telemetry, handshakes,
/// heartbeats, and control messages into binary packets with framing and checksums.
///
/// Packet Wire Format:
/// ```
/// +--------------------+---------------+------------------+-------------------+--------------------+
/// | Header (2 bytes)   | Type (1 byte) | Length (2 bytes) | Payload (N bytes) | Checksum (2 bytes) |
/// | 0x56 0x4E ('VN')   | PacketType    | Big-Endian UInt16| Arbitrary Binary  | CRC16 Big-Endian   |
/// +--------------------+---------------+------------------+-------------------+--------------------+
/// ```
public struct PacketEncoder {

    // MARK: - Constants

    /// Magic byte 0: 'V' (0x56)
    public static let headerMagic0: UInt8 = 0x56

    /// Magic byte 1: 'N' (0x4E)
    public static let headerMagic1: UInt8 = 0x4E

    /// Combined 2-byte magic header array [0x56, 0x4E].
    public static let magicHeader: [UInt8] = [headerMagic0, headerMagic1]

    /// Fixed length of header magic bytes.
    public static let headerLength: Int = 2

    /// Fixed length of type identifier byte.
    public static let typeLength: Int = 1

    /// Fixed length of payload length field.
    public static let lengthFieldLength: Int = 2

    /// Fixed length of CRC16 checksum field.
    public static let checksumLength: Int = 2

    /// Total framing overhead: Header (2) + Type (1) + Length (2) + Checksum (2) = 7 bytes.
    public static let framingOverhead: Int = headerLength + typeLength + lengthFieldLength + checksumLength

    private init() {}

    // MARK: - Generic Framing

    /// Encodes a raw payload into a framed packet with header, type, length, and CRC16 checksum.
    ///
    /// - Parameters:
    ///   - type: The packet type identifier.
    ///   - payload: The arbitrary binary payload to encapsulate (defaults to empty).
    /// - Returns: Complete framed binary packet data.
    public static func encodePacket(type: PacketType, payload: Data = Data()) -> Data {
        let payloadCount = min(payload.count, Int(UInt16.max))
        var packet = Data()
        packet.reserveCapacity(framingOverhead + payloadCount)

        // 1. Header (2 bytes: 0x56, 0x4E)
        packet.append(headerMagic0)
        packet.append(headerMagic1)

        // 2. Type (1 byte)
        packet.append(type.rawValue)

        // 3. Length (2 bytes, big-endian)
        let lengthUInt16 = UInt16(payloadCount)
        packet.append(UInt8((lengthUInt16 >> 8) & 0xFF))
        packet.append(UInt8(lengthUInt16 & 0xFF))

        // 4. Payload (N bytes)
        if payloadCount > 0 {
            if payload.count > payloadCount {
                packet.append(payload.prefix(payloadCount))
            } else {
                packet.append(payload)
            }
        }

        // 5. Checksum (2 bytes, CRC16 over Header + Type + Length + Payload)
        let checksum = crc16(packet)
        packet.append(UInt8((checksum >> 8) & 0xFF))
        packet.append(UInt8(checksum & 0xFF))

        return packet
    }

    // MARK: - Specialized Encoders

    /// Encodes the complete instantaneous state of the controller into a binary packet.
    ///
    /// The payload adheres to the 19-byte compact format:
    /// - buttons: UInt32 (4 bytes big-endian)
    /// - leftStickX: UInt8 (1 byte, 0-255, 128 center)
    /// - leftStickY: UInt8 (1 byte, 0-255, 128 center)
    /// - rightStickX: UInt8 (1 byte, 0-255, 128 center)
    /// - rightStickY: UInt8 (1 byte, 0-255, 128 center)
    /// - leftTrigger: UInt8 (1 byte, 0-255)
    /// - rightTrigger: UInt8 (1 byte, 0-255)
    /// - dpadState: UInt8 (1 byte, 0-8)
    /// - timestamp: UInt64 (8 bytes big-endian monotonic milliseconds)
    ///
    /// - Parameter state: The controller state snapshot to encode.
    /// - Returns: Framed packet ready for Bluetooth or Wi-Fi transport.
    public static func encode(_ state: ControllerState) -> Data {
        encodePacket(type: .controllerState, payload: state.toData())
    }

    /// Encodes a periodic heartbeat / ping packet with the current monotonic timestamp.
    ///
    /// - Parameter timestamp: Monotonic millisecond timestamp (defaults to current time).
    /// - Returns: Framed heartbeat packet.
    public static func encodeHeartbeat(timestamp: UInt64 = Date.monotonicMilliseconds) -> Data {
        var payload = Data(capacity: 8)
        var tsBig = timestamp.bigEndian
        withUnsafeBytes(of: &tsBig) { payload.append(contentsOf: $0) }
        return encodePacket(type: .heartbeat, payload: payload)
    }

    /// Encodes a handshake initiation packet carrying the client device name.
    ///
    /// - Parameter deviceName: The human-readable name of the iOS device (e.g., UIDevice.current.name).
    /// - Returns: Framed handshake packet.
    public static func encodeHandshake(deviceName: String) -> Data {
        let utf8Data = Data(deviceName.utf8)
        return encodePacket(type: .handshake, payload: utf8Data)
    }

    /// Encodes a graceful disconnect request packet.
    ///
    /// - Parameter reason: Optional status byte representing the disconnect reason (defaults to 0).
    /// - Returns: Framed disconnect packet.
    public static func encodeDisconnect(reason: UInt8 = 0) -> Data {
        let payload = Data([reason])
        return encodePacket(type: .disconnect, payload: payload)
    }

    /// Encodes an acknowledgment packet for round-trip latency measurement and delivery confirmation.
    ///
    /// - Parameter sequence: The 16-bit sequence number being acknowledged.
    /// - Returns: Framed ack packet.
    public static func encodeAck(sequence: UInt16) -> Data {
        var payload = Data(capacity: 2)
        var seqBig = sequence.bigEndian
        withUnsafeBytes(of: &seqBig) { payload.append(contentsOf: $0) }
        return encodePacket(type: .ack, payload: payload)
    }

    /// Encodes a profile or configuration packet.
    ///
    /// - Parameter configData: Serialized profile or configuration binary data.
    /// - Returns: Framed config packet.
    public static func encodeConfig(_ configData: Data) -> Data {
        encodePacket(type: .config, payload: configData)
    }

    // MARK: - CRC16 Checksum

    /// Computes the CRC-16 (CCITT-FALSE: polynomial 0x1021, init 0xFFFF, no reflection)
    /// across the provided binary data.
    ///
    /// - Parameter data: The data buffer to checksum.
    /// - Returns: 16-bit checksum value.
    public static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= (UInt16(byte) &<< 8)
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc &<< 1) ^ 0x1021
                } else {
                    crc = crc &<< 1
                }
            }
        }
        return crc
    }

    /// Computes CRC16 across a raw byte array.
    public static func crc16(_ bytes: [UInt8]) -> UInt16 {
        crc16(Data(bytes))
    }

    // MARK: - AES-256 Encryption

    /// Encrypts arbitrary binary data using AES-256.
    /// Uses CryptoKit AES-GCM when available, and falls back to CommonCrypto AES-256-CBC.
    ///
    /// - Parameters:
    ///   - data: Plaintext data to encrypt.
    ///   - key: Secret key data. If fewer or more than 32 bytes (256 bits), a SHA-256 hash
    ///          is derived to guarantee a valid 256-bit symmetric key.
    /// - Returns: Combined encrypted ciphertext payload, or nil if encryption failed.
    public static func encrypt(_ data: Data, key: Data) -> Data? {
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
                let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
                return sealedBox.combined
            } catch {
                // If CryptoKit fails for any reason, attempt CommonCrypto fallback
            }
        }
        #endif

        #if canImport(CommonCrypto)
        return commonCryptoEncrypt(data, key: key)
        #else
        return nil
        #endif
    }

    #if canImport(CommonCrypto)
    /// CommonCrypto fallback encryptor using AES-256-CBC with PKCS7 padding.
    /// Prepends a 16-byte random IV to the resulting ciphertext.
    private static func commonCryptoEncrypt(_ data: Data, key: Data) -> Data? {
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

        var iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        let status = SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv)
        guard status == errSecSuccess else { return nil }

        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var numBytesEncrypted: size_t = 0

        let cryptStatus = keyBytes.withUnsafeBytes { keyBuf in
            data.withUnsafeBytes { dataBuf in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    keyBuf.baseAddress,
                    keyLength,
                    iv,
                    dataBuf.baseAddress,
                    data.count,
                    &buffer,
                    bufferSize,
                    &numBytesEncrypted
                )
            }
        }

        guard cryptStatus == kCCSuccess else { return nil }
        var result = Data(iv)
        result.append(contentsOf: buffer.prefix(numBytesEncrypted))
        return result
    }
    #endif
}
