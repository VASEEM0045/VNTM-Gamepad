# 🎮 VNTM Gamepad — Windows Companion Server (Option 3: Rust)

High-performance, ultra-low-latency Windows companion server for the **VNTM Gamepad** iOS app.

## Features
- **Ultra-low latency**: Native async socket server (Tokio) with `TCP_NODELAY` disabled Nagle's algorithm for sub-millisecond packet reception (<1ms overhead).
- **ViGEmBus Xbox 360 Emulation**: Injects inputs as a real Virtual Xbox 360 controller into Windows, making it natively compatible with Steam, Epic Games, Game Pass, emulators, etc.
- **Auto-Discovery via Bonjour/mDNS**: Broadcasts `_vntmgamepad._tcp.local.` on port `7777`. Your iPhone discovers your PC automatically without manually typing IP addresses.
- **Live Terminal HUD**: Displays real-time packet update rate (Hz), ping latency, pressed buttons, triggers, and thumbstick coordinates.
- **Simulation Fallback Mode**: If ViGEmBus driver is not yet installed, runs in simulation mode so you can test network discovery and input streaming immediately.

---

## Prerequisites (For Real Gamepad Emulation)

To make Windows games recognize your iPhone as a real Xbox 360 controller, install the **ViGEmBus driver** (one-time install):
👉 **Download ViGEmBus**: [https://github.com/nefarius/ViGEmBus/releases/latest](https://github.com/nefarius/ViGEmBus/releases/latest) (Download `ViGEmBus_Setup_x64.exe` and install).

*(Note: Even without this driver, the server will still run in Simulation Mode and display live inputs in the console!)*

---

## How to Run

### Method 1: Double-click Launcher
Double-click `run-server.bat` in the project root directory.

### Method 2: Command Line
```powershell
cd "VNTMGamepad-Server"
cargo run --release
```

Or run the compiled executable directly:
```powershell
.\target\release\vntmgamepad-server.exe
```

---

## Connecting from iPhone
1. Ensure your iPhone and Windows PC are connected to the same Wi-Fi network.
2. Launch the **VNTM Gamepad** iOS app on your iPhone.
3. Switch to the **Connection** tab.
4. Your PC will appear under discovered devices (e.g. `VNTM-YourPC`).
5. Tap **Connect**!
