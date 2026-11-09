//! VNTM Gamepad - Windows Companion Server (Option 3: Rust High-Performance)
//! Ultra-low-latency TCP socket receiver and ViGEm virtual Xbox 360 controller emulator

mod gamepad;
mod mdns;
mod protocol;

use colored::*;
use gamepad::VirtualGamepad;
use mdns::MdnsAdvertiser;
use protocol::{parse_packet, ControllerState, PacketType};
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const PORT: u16 = 7777;
const PING_HEADER: [u8; 4] = [0x50, 0x49, 0x4E, 0x47]; // "PING"
const PONG_HEADER: [u8; 4] = [0x50, 0x4F, 0x4E, 0x47]; // "PONG"

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    print_banner();

    // 1. Detect Local Network IP
    let local_ip = local_ip_address::local_ip()
        .map(|ip| ip.to_string())
        .unwrap_or_else(|_| "127.0.0.1".to_string());

    println!("{} Local IP: {}", "[Network]".blue().bold(), local_ip.bright_white().bold());
    println!("{} Listening Port: {}", "[Network]".blue().bold(), PORT.to_string().bright_white().bold());

    // 2. Start mDNS / Bonjour Advertising for iOS Auto-Discovery
    let mut mdns = MdnsAdvertiser::new();
    mdns.start(PORT);

    // 3. Initialize ViGEm Xbox 360 Virtual Gamepad
    let mut gamepad = VirtualGamepad::new();

    // 4. Start TCP Listener with Low-Latency Socket Config
    let listener = TcpListener::bind(format!("0.0.0.0:{}", PORT)).await?;
    println!(
        "{} TCP Server waiting for iOS connection on {}:{}...",
        "[Status]".green().bold(),
        local_ip.cyan(),
        PORT
    );

    println!(
        "\n{}\n",
        "Tip: Open VNTM Gamepad app on your iPhone -> Connection -> Tap your PC!".bright_black()
    );

    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();

    // Spawn graceful CTRL+C handler
    tokio::spawn(async move {
        let _ = tokio::signal::ctrl_c().await;
        println!("\n{}", "Received shutdown signal. Exiting gracefully...".yellow().bold());
        r.store(false, Ordering::SeqCst);
        std::process::exit(0);
    });

    while running.load(Ordering::SeqCst) {
        match listener.accept().await {
            Ok((stream, peer_addr)) => {
                println!(
                    "\n{} Client connected from {}",
                    "[Connected]".green().bold(),
                    peer_addr.to_string().bright_green()
                );

                handle_client(stream, peer_addr, &mut gamepad).await;

                println!(
                    "{} Client disconnected. Resetting controller to neutral.",
                    "[Disconnected]".yellow().bold()
                );
                gamepad.reset_neutral();
            }
            Err(e) => {
                eprintln!("{} Failed to accept connection: {:?}", "[Error]".red(), e);
            }
        }
    }

    Ok(())
}

/// Handles a connected iOS client stream until disconnection.
async fn handle_client(
    mut stream: TcpStream,
    _peer_addr: SocketAddr,
    gamepad: &mut VirtualGamepad,
) {
    // Disable Nagle's algorithm for sub-millisecond packet latency
    let _ = stream.set_nodelay(true);

    let mut buffer = Vec::with_capacity(4096);
    let mut chunk = [0u8; 1024];

    let mut packet_count: u64 = 0;
    let mut last_hud_time = Instant::now();
    let mut last_second_time = Instant::now();
    let mut packets_this_second: u32 = 0;
    let mut current_hz: u32 = 0;
    let mut device_name = "iOS Gamepad".to_string();

    loop {
        tokio::select! {
            result = stream.read(&mut chunk) => {
                match result {
                    Ok(0) => {
                        // Connection closed by client
                        break;
                    }
                    Ok(bytes_read) => {
                        buffer.extend_from_slice(&chunk[..bytes_read]);

                        // Handle raw PING -> PONG responses (used by WiFiService.swift)
                        handle_ping_pong(&mut buffer, &mut stream).await;

                        // Parse binary framed packets
                        while let Some(packet) = parse_packet(&mut buffer) {
                            packet_count += 1;
                            packets_this_second += 1;

                            match packet.packet_type {
                                PacketType::Handshake => {
                                    if let Ok(name) = String::from_utf8(packet.payload) {
                                        device_name = name;
                                        println!(
                                            "{} Handshake received from device: {}",
                                            "[Handshake]".cyan().bold(),
                                            device_name.bright_white().bold()
                                        );
                                    }
                                    // Send ACK back
                                    let ack = protocol::encode_packet(PacketType::Ack, &[0x00, 0x01]);
                                    let _ = stream.write_all(&ack).await;
                                }
                                PacketType::Heartbeat => {
                                    // Echo back heartbeat payload for iOS RTT latency calculation
                                    let response = protocol::encode_packet(PacketType::Heartbeat, &packet.payload);
                                    let _ = stream.write_all(&response).await;
                                }
                                PacketType::ControllerState => {
                                    if let Some(state) = ControllerState::parse(&packet.payload) {
                                        gamepad.update(&state);

                                        // Render live terminal HUD at ~15fps (every 66ms) so console doesn't flicker
                                        if last_hud_time.elapsed() >= Duration::from_millis(66) {
                                            render_hud(&state, current_hz, packet_count, &device_name, gamepad.is_simulated());
                                            last_hud_time = Instant::now();
                                        }
                                    }
                                }
                                PacketType::Disconnect => {
                                    println!("\n{} Client sent graceful disconnect packet.", "[Notice]".yellow());
                                    gamepad.reset_neutral();
                                    return;
                                }
                                PacketType::Ack | PacketType::Config | PacketType::Unknown(_) => {}
                            }
                        }

                        // Calculate packet update rate (Hz)
                        if last_second_time.elapsed() >= Duration::from_secs(1) {
                            current_hz = packets_this_second;
                            packets_this_second = 0;
                            last_second_time = Instant::now();
                        }
                    }
                    Err(e) => {
                        eprintln!("\n{} TCP socket read error: {:?}", "[Socket Error]".red(), e);
                        break;
                    }
                }
            }
        }
    }
}

/// Evaluates buffer for direct "PING" + timestamp packets from WiFiService.swift and replies with "PONG".
async fn handle_ping_pong(buffer: &mut Vec<u8>, stream: &mut TcpStream) {
    if buffer.len() >= 12 && buffer[..4] == PING_HEADER {
        let timestamp_bytes = &buffer[4..12];
        let mut pong = Vec::with_capacity(12);
        pong.extend_from_slice(&PONG_HEADER);
        pong.extend_from_slice(timestamp_bytes);
        let _ = stream.write_all(&pong).await;
        buffer.drain(0..12);
    }
}

/// Renders a real-time single-line HUD of controller inputs in the console.
fn render_hud(state: &ControllerState, hz: u32, total_packets: u64, device: &str, is_simulated: bool) {
    let mode_badge = if is_simulated {
        "[SIMULATED]".yellow()
    } else {
        "[XINPUT OK]".green()
    };

    let btn_a = if state.is_button_pressed(1) { "A".green().bold() } else { "A".dimmed() };
    let btn_b = if state.is_button_pressed(2) { "B".red().bold() } else { "B".dimmed() };
    let btn_x = if state.is_button_pressed(4) { "X".blue().bold() } else { "X".dimmed() };
    let btn_y = if state.is_button_pressed(8) { "Y".yellow().bold() } else { "Y".dimmed() };
    let btn_lb = if state.is_button_pressed(16) { "LB".white().bold() } else { "LB".dimmed() };
    let btn_rb = if state.is_button_pressed(32) { "RB".white().bold() } else { "RB".dimmed() };

    let lt_pct = (state.left_trigger as f32 / 255.0 * 100.0) as u32;
    let rt_pct = (state.right_trigger as f32 / 255.0 * 100.0) as u32;

    print!(
        "\r{} {} | Rate: {} Hz | BTNS: [{} {} {} {}] [{} {}] | LT:{:3}% RT:{:3}% | L:({:3},{:3}) R:({:3},{:3}) | Total: {}   ",
        mode_badge,
        device.bright_cyan(),
        format!("{:3}", hz).bright_white().bold(),
        btn_a, btn_b, btn_x, btn_y,
        btn_lb, btn_rb,
        lt_pct, rt_pct,
        state.left_stick_x, state.left_stick_y,
        state.right_stick_x, state.right_stick_y,
        total_packets
    );
    use std::io::Write;
    let _ = std::io::stdout().flush();
}

fn print_banner() {
    let banner = r#"
██╗   ██╗███╗   ██╗████████╗███╗   ███╗     ██████╗  █████╗ ███╗   ███╗███████╗██████╗  █████╗ ██████╗ 
██║   ██║████╗  ██║╚══██╔══╝████╗ ████║    ██╔════╝ ██╔══██╗████╗ ████║██╔════╝██╔══██╗██╔══██╗██╔══██╗
██║   ██║██╔██╗ ██║   ██║   ██╔████╔██║    ██║  ███╗███████║██╔████╔██║█████╗  ██████╔╝███████║██║  ██║
╚██╗ ██╔╝██║╚██╗██║   ██║   ██║╚██╔╝██║    ██║   ██║██╔══██║██║╚██╔╝██║██╔══╝  ██╔═══╝ ██╔══██║██║  ██║
 ╚████╔╝ ██║ ╚████║   ██║   ██║ ╚═╝ ██║    ╚██████╔╝██║  ██║██║ ╚═╝ ██║███████╗██║     ██║  ██║██████╔╝
  ╚═══╝  ╚═╝  ╚═══╝   ╚═╝   ╚═╝     ╚═╝     ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝╚═════╝ 
"#;
    println!("{}", banner.bright_cyan().bold());
    println!(
        "{} {}",
        "=== VNTM Gamepad Windows Server (Rust Ultra-Low Latency Edition) ===".bright_white().bold(),
        "v1.0.0".dimmed()
    );
    println!("Architecture: Native Async I/O (Tokio) + ViGEmBus Virtual Xbox 360 Emulation\n");
}
