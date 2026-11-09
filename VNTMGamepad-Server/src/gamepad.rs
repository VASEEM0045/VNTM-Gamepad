//! ViGEmBus Xbox 360 Virtual Gamepad Emulation
//! Translates VNTM Gamepad inputs to Windows XInput events

use colored::*;
use vigem_client::{Client, TargetId, XButtons, XGamepad, XTarget};
use crate::protocol::ControllerState;

/// Digital Button bitmasks from ButtonMask.swift
const BTN_A: u32 = 1;
const BTN_B: u32 = 2;
const BTN_X: u32 = 4;
const BTN_Y: u32 = 8;
const BTN_LB: u32 = 16;
const BTN_RB: u32 = 32;
const BTN_START: u32 = 64;
const BTN_SELECT: u32 = 128;
const BTN_HOME: u32 = 256;
const BTN_LEFT_STICK: u32 = 512;
const BTN_RIGHT_STICK: u32 = 1024;

/// Standard XInput button bit flags
const XUSB_GAMEPAD_DPAD_UP: u16 = 0x0001;
const XUSB_GAMEPAD_DPAD_DOWN: u16 = 0x0002;
const XUSB_GAMEPAD_DPAD_LEFT: u16 = 0x0004;
const XUSB_GAMEPAD_DPAD_RIGHT: u16 = 0x0008;
const XUSB_GAMEPAD_START: u16 = 0x0010;
const XUSB_GAMEPAD_BACK: u16 = 0x0020;
const XUSB_GAMEPAD_LEFT_THUMB: u16 = 0x0040;
const XUSB_GAMEPAD_RIGHT_THUMB: u16 = 0x0080;
const XUSB_GAMEPAD_LEFT_SHOULDER: u16 = 0x0100;
const XUSB_GAMEPAD_RIGHT_SHOULDER: u16 = 0x0200;
const XUSB_GAMEPAD_GUIDE: u16 = 0x0400;
const XUSB_GAMEPAD_A: u16 = 0x1000;
const XUSB_GAMEPAD_B: u16 = 0x2000;
const XUSB_GAMEPAD_X: u16 = 0x4000;
const XUSB_GAMEPAD_Y: u16 = 0x8000;

pub struct VirtualGamepad {
    target: Option<XTarget>,
    is_simulated: bool,
}

impl VirtualGamepad {
    /// Initializes the ViGEm virtual Xbox 360 controller or enters simulated mode.
    pub fn new() -> Self {
        match Client::connect() {
            Ok(client) => {
                let mut target = XTarget::new(client, TargetId::XBOX360_WIRED);
                if let Err(e) = target.plugin() {
                    eprintln!(
                        "{} Failed to plug in virtual Xbox 360 controller: {:?}",
                        "[ViGEm Error]".red().bold(),
                        e
                    );
                    return Self::simulated();
                }

                if let Err(e) = target.wait_ready() {
                    eprintln!(
                        "{} ViGEm target failed wait_ready: {:?}",
                        "[ViGEm Warning]".yellow(),
                        e
                    );
                }

                println!(
                    "{} {}",
                    "[ViGEmBus]".green().bold(),
                    "Virtual Xbox 360 Controller connected to Windows!".bold()
                );

                VirtualGamepad {
                    target: Some(target),
                    is_simulated: false,
                }
            }
            Err(e) => {
                eprintln!(
                    "\n{}\n{} Could not connect to ViGEmBus driver: {:?}\n{}\n{}\n",
                    "============================================================".yellow(),
                    "[ViGEmBus Notice]".yellow().bold(),
                    e,
                    "-> To enable real gamepad input in PC games, install ViGEmBus:".bright_white(),
                    "   https://github.com/nefarius/ViGEmBus/releases/latest".cyan().underline()
                );
                eprintln!(
                    "{}\n============================================================\n",
                    "-> Running in SIMULATION MODE: Telemetry and network active.".bright_cyan()
                );
                Self::simulated()
            }
        }
    }

    fn simulated() -> Self {
        VirtualGamepad {
            target: None,
            is_simulated: true,
        }
    }

    pub fn is_simulated(&self) -> bool {
        self.is_simulated
    }

    /// Updates the Xbox 360 virtual gamepad with new controller state.
    pub fn update(&mut self, state: &ControllerState) {
        if let Some(target) = &mut self.target {
            let mut xbuttons: u16 = 0;

            // ABXY & Face buttons
            if (state.buttons & BTN_A) != 0 { xbuttons |= XUSB_GAMEPAD_A; }
            if (state.buttons & BTN_B) != 0 { xbuttons |= XUSB_GAMEPAD_B; }
            if (state.buttons & BTN_X) != 0 { xbuttons |= XUSB_GAMEPAD_X; }
            if (state.buttons & BTN_Y) != 0 { xbuttons |= XUSB_GAMEPAD_Y; }

            // Shoulders & Bumpers
            if (state.buttons & BTN_LB) != 0 { xbuttons |= XUSB_GAMEPAD_LEFT_SHOULDER; }
            if (state.buttons & BTN_RB) != 0 { xbuttons |= XUSB_GAMEPAD_RIGHT_SHOULDER; }

            // Special / Menu buttons
            if (state.buttons & BTN_START) != 0 { xbuttons |= XUSB_GAMEPAD_START; }
            if (state.buttons & BTN_SELECT) != 0 { xbuttons |= XUSB_GAMEPAD_BACK; }
            if (state.buttons & BTN_HOME) != 0 { xbuttons |= XUSB_GAMEPAD_GUIDE; }

            // Thumb clicks
            if (state.buttons & BTN_LEFT_STICK) != 0 { xbuttons |= XUSB_GAMEPAD_LEFT_THUMB; }
            if (state.buttons & BTN_RIGHT_STICK) != 0 { xbuttons |= XUSB_GAMEPAD_RIGHT_THUMB; }

            // D-Pad Direction Mapping (0..8)
            match state.dpad {
                1 => xbuttons |= XUSB_GAMEPAD_DPAD_UP,
                2 => xbuttons |= XUSB_GAMEPAD_DPAD_UP | XUSB_GAMEPAD_DPAD_RIGHT,
                3 => xbuttons |= XUSB_GAMEPAD_DPAD_RIGHT,
                4 => xbuttons |= XUSB_GAMEPAD_DPAD_DOWN | XUSB_GAMEPAD_DPAD_RIGHT,
                5 => xbuttons |= XUSB_GAMEPAD_DPAD_DOWN,
                6 => xbuttons |= XUSB_GAMEPAD_DPAD_DOWN | XUSB_GAMEPAD_DPAD_LEFT,
                7 => xbuttons |= XUSB_GAMEPAD_DPAD_LEFT,
                8 => xbuttons |= XUSB_GAMEPAD_DPAD_UP | XUSB_GAMEPAD_DPAD_LEFT,
                _ => {}
            }

            let report = XGamepad {
                buttons: XButtons { raw: xbuttons },
                left_trigger: state.left_trigger,
                right_trigger: state.right_trigger,
                thumb_lx: Self::map_stick(state.left_stick_x),
                thumb_ly: Self::map_stick(state.left_stick_y),
                thumb_rx: Self::map_stick(state.right_stick_x),
                thumb_ry: Self::map_stick(state.right_stick_y),
            };

            let _ = target.update(&report);
        }
    }

    /// Resets all controls to neutral zero state.
    pub fn reset_neutral(&mut self) {
        if let Some(target) = &mut self.target {
            let report = XGamepad::default();
            let _ = target.update(&report);
        }
    }

    /// Converts 0..255 (center 128) thumbstick byte to XInput -32768..=32767.
    fn map_stick(val: u8) -> i16 {
        if val == 128 {
            0
        } else if val > 128 {
            let fraction = (val - 128) as f32 / 127.0;
            (fraction * 32767.0).round().min(32767.0) as i16
        } else {
            let fraction = (128 - val) as f32 / 128.0;
            (-fraction * 32768.0).round().max(-32768.0) as i16
        }
    }
}

impl Drop for VirtualGamepad {
    fn drop(&mut self) {
        if let Some(mut target) = self.target.take() {
            let report = XGamepad::default();
            let _ = target.update(&report);
            let _ = target.unplug();
        }
    }
}
