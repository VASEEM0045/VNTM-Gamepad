# VNTM Gamepad

[![Build Status](https://github.com/vntm/vntm-gamepad-ios/workflows/CI/badge.svg)](https://github.com/vntm/vntm-gamepad-ios/actions)
[![Release](https://img.shields.io/github/v/release/vntm/vntm-gamepad-ios?color=blue)](https://github.com/vntm/vntm-gamepad-ios/releases)
[![iOS 15.0+](https://img.shields.io/badge/iOS-15.0%2B-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**VNTM Gamepad** transforms your iPhone into a high-performance, low-latency wireless gamepad controller for PC gaming. Communicating over Bluetooth Low Energy (BLE) or high-speed local Wi-Fi (UDP/TCP), it provides console-grade responsiveness, customizable ergonomics, motion gyro controls, and deep configuration profiles.

Designed for standard iOS installations as well as non-sandboxed environments via **TrollStore**.

---

## Features

- **Ultra Low Latency Transports**:
  - **Bluetooth Low Energy (BLE)**: Custom GATT service with coalesced input batching at up to 60Hz/120Hz.
  - **Wi-Fi Companion Link**: High-throughput UDP/TCP transport with automatic Bonjour (`_vntmgamepad._tcp`) discovery.
- **Full Console Gamepad Layout**:
  - Virtual dual analog thumbsticks with dynamic centering, custom deadzones, and sensitivity curves.
  - Action buttons (`A`, `B`, `X`, `Y`), bumpers (`LB`, `RB`), triggers (`LT`, `RT`), and system controls (`Start`, `Select`, `Home`).
  - Directional Pad (D-Pad) with diagonal input smoothing.
- **Motion / Gyro Controls**:
  - Gyroscope and accelerometer integration for motion-assisted aiming and tilt-based steering.
- **Advanced Haptics**:
  - CoreHaptics integration providing crisp feedback on button actuations and trigger pulls.
- **Custom Controller Profiles**:
  - Multi-profile management to save, duplicate, and switch between customized button mappings, deadzones, and sensitivities.
- **Diagnostics & Telemetry**:
  - Live RTT (round-trip time), packet transfer rates, RSSI tracking, and in-memory event logging buffer.
- **TrollStore & Sideloading Ready**:
  - Preconfigured entitlements with disabled app-sandbox and multicast networking permissions.

---

## Requirements

- **iOS Target**: iOS 15.0 or later
- **Device Support**: iPhone (supports Portrait and Landscape orientations)
- **Development Tooling**:
  - macOS with Xcode 15.0+ and Swift 5.9+
  - [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

---

## Project Structure

```
├── VNTMGamepad/
│   ├── Info.plist                     # Application configuration & permissions
│   ├── VNTMGamepad.entitlements       # Network multicast & TrollStore entitlements
│   ├── Models/                        # State representations & controller profiles
│   │   ├── ControllerProfile.swift
│   │   └── ControllerState.swift
│   └── Utilities/                     # Constants, extensions, logger, and persistence
│       ├── Constants.swift
│       ├── Extensions.swift
│       ├── InputMapping.swift
│       ├── Logger.swift
│       └── Persistence.swift
├── VNTMGamepadTests/                  # Unit test suite
├── project.yml                        # XcodeGen project specification
├── .gitignore                         # Standard Swift / Xcode ignores
└── README.md                          # Project documentation
```

---

## Build & Setup Instructions

### 1. Prerequisites

Install XcodeGen via Homebrew (on macOS):

```bash
brew install xcodegen
```

### 2. Generate the Xcode Project

Generate `VNTMGamepad.xcodeproj` from `project.yml`:

```bash
xcodegen generate
```

### 3. Open and Build in Xcode

```bash
open VNTMGamepad.xcodeproj
```

Select your target device or simulator in Xcode and press `Cmd + B` to build, or `Cmd + R` to run.

### 4. Command Line Build

To build from the terminal using `xcodebuild`:

```bash
xcodebuild -project VNTMGamepad.xcodeproj \
           -scheme VNTMGamepad \
           -configuration Release \
           -destination "generic/platform=iOS" \
           CODE_SIGNING_ALLOWED=NO
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
