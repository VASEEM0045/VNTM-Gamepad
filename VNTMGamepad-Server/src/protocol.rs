//! Binary Wire Protocol for VNTM Gamepad
//! Matches PacketEncoder.swift / PacketDecoder.swift / ControllerState.swift

/// Magic header bytes: "VN" (0x56, 0x4E)
pub const HEADER_MAGIC: [u8; 2] = [0x56, 0x4E];
pub const HEADER_SIZE: usize = 7; // Header(2) + Type(1) + Length(2) + Checksum(2)

/// Packet types defined by the iOS client.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PacketType {
    ControllerState = 0x01,
    Heartbeat = 0x02,
    Config = 0x03,
    Handshake = 0x04,
    Disconnect = 0x05,
    Ack = 0x06,
    Unknown(u8),
}

impl From<u8> for PacketType {
    fn from(val: u8) -> Self {
        match val {
            0x01 => PacketType::ControllerState,
            0x02 => PacketType::Heartbeat,
            0x03 => PacketType::Config,
            0x04 => PacketType::Handshake,
            0x05 => PacketType::Disconnect,
            0x06 => PacketType::Ack,
            other => PacketType::Unknown(other),
        }
    }
}

/// Instantaneous controller snapshot received from the iOS app.
#[derive(Debug, Clone, Default)]
pub struct ControllerState {
    pub buttons: u32,
    pub left_stick_x: u8,
    pub left_stick_y: u8,
    pub right_stick_x: u8,
    pub right_stick_y: u8,
    pub left_trigger: u8,
    pub right_trigger: u8,
    pub dpad: u8,
    pub timestamp: u64,
}

impl ControllerState {
    /// Deserializes a 19-byte compact payload into a ControllerState.
    pub fn parse(payload: &[u8]) -> Option<Self> {
        if payload.len() < 19 {
            return None;
        }

        let buttons = u32::from_be_bytes([payload[0], payload[1], payload[2], payload[3]]);
        let left_stick_x = payload[4];
        let left_stick_y = payload[5];
        let right_stick_x = payload[6];
        let right_stick_y = payload[7];
        let left_trigger = payload[8];
        let right_trigger = payload[9];
        let dpad = payload[10];
        let timestamp = u64::from_be_bytes([
            payload[11], payload[12], payload[13], payload[14],
            payload[15], payload[16], payload[17], payload[18],
        ]);

        Some(ControllerState {
            buttons,
            left_stick_x,
            left_stick_y,
            right_stick_x,
            right_stick_y,
            left_trigger,
            right_trigger,
            dpad,
            timestamp,
        })
    }

    pub fn is_button_pressed(&self, mask: u32) -> bool {
        (self.buttons & mask) != 0
    }
}

/// Computes CRC16-CCITT-FALSE (poly 0x1021, init 0xFFFF, no reflection).
/// Identical to PacketEncoder.swift `crc16(_:)`.
pub fn crc16(data: &[u8]) -> u16 {
    let mut crc: u16 = 0xFFFF;
    for &byte in data {
        crc ^= (byte as u16) << 8;
        for _ in 0..8 {
            if (crc & 0x8000) != 0 {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc <<= 1;
            }
        }
    }
    crc
}

/// Encapsulates a decoded binary packet.
#[derive(Debug, Clone)]
pub struct DecodedPacket {
    pub packet_type: PacketType,
    pub payload: Vec<u8>,
}

/// Parses the next available packet from the streaming buffer, removing consumed bytes.
pub fn parse_packet(buffer: &mut Vec<u8>) -> Option<DecodedPacket> {
    loop {
        if buffer.len() < HEADER_SIZE {
            return None;
        }

        // Search for magic bytes "VN"
        if buffer[0] != HEADER_MAGIC[0] || buffer[1] != HEADER_MAGIC[1] {
            buffer.remove(0);
            continue;
        }

        let packet_type = PacketType::from(buffer[2]);
        let payload_len = u16::from_be_bytes([buffer[3], buffer[4]]) as usize;
        let total_packet_len = 5 + payload_len + 2; // Header(2) + Type(1) + Len(2) + Payload + CRC(2)

        if buffer.len() < total_packet_len {
            // Incomplete packet in stream, wait for more data
            return None;
        }

        // Verify CRC16 over Header + Type + Length + Payload
        let check_slice = &buffer[0..(5 + payload_len)];
        let expected_crc = crc16(check_slice);
        let actual_crc = u16::from_be_bytes([
            buffer[5 + payload_len],
            buffer[5 + payload_len + 1],
        ]);

        if expected_crc != actual_crc {
            // Checksum failed, discard header magic to resynchronize
            buffer.drain(0..2);
            continue;
        }

        // Extract payload
        let payload = buffer[5..(5 + payload_len)].to_vec();

        // Remove packet from stream buffer
        buffer.drain(0..total_packet_len);

        return Some(DecodedPacket {
            packet_type,
            payload,
        });
    }
}

/// Encodes a framed packet to send back to iOS.
pub fn encode_packet(packet_type: PacketType, payload: &[u8]) -> Vec<u8> {
    let type_byte = match packet_type {
        PacketType::ControllerState => 0x01,
        PacketType::Heartbeat => 0x02,
        PacketType::Config => 0x03,
        PacketType::Handshake => 0x04,
        PacketType::Disconnect => 0x05,
        PacketType::Ack => 0x06,
        PacketType::Unknown(val) => val,
    };

    let len = payload.len() as u16;
    let mut packet = Vec::with_capacity(7 + payload.len());
    packet.extend_from_slice(&HEADER_MAGIC);
    packet.push(type_byte);
    packet.extend_from_slice(&len.to_be_bytes());
    packet.extend_from_slice(payload);

    let crc = crc16(&packet);
    packet.extend_from_slice(&crc.to_be_bytes());
    packet
}
