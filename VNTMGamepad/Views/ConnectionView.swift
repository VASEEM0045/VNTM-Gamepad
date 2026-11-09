//
//  ConnectionView.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//  MVVM Architecture with Combine Framework
//

import SwiftUI

/// Device discovery, transport configuration, and real-time telemetry screen.
///
/// Enables Bluetooth Low Energy and local Wi-Fi pairing, manual TCP host entry,
/// live ping and packet telemetry inspection, and automated backoff session recovery.
public struct ConnectionView: View {

    // MARK: - Injected ViewModels

    @EnvironmentObject private var connectionVM: ConnectionViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    // MARK: - Local State

    @State private var manualHost: String = "192.168.1.100"
    @State private var manualPort: String = "7777"
    @State private var isShowingManualEntry: Bool = false
    @State private var radarPulse: Bool = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Background
            Color(hex: 0x0C1017)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: Transport Segmented Control
                    transportPickerSection

                    // MARK: Connected Device Card (if connected or active session)
                    if connectionVM.status == .connected, let device = connectionVM.selectedDevice {
                        connectedDeviceCard(device: device)
                    }

                    // MARK: Scanning Radar / Header Action
                    scanningStatusBar

                    // MARK: Discovered Devices List
                    discoveredDevicesSection

                    // MARK: Manual Wi-Fi Configuration
                    if connectionVM.connectionType == .wifi {
                        manualWiFiSection
                    }

                    // MARK: Session & Recovery Preferences
                    preferencesSection

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .refreshable {
                connectionVM.refreshDevices()
                connectionVM.startScanning()
            }
        }
        .navigationTitle("Device Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if connectionVM.status == .scanning {
                    Button("Stop") {
                        connectionVM.stopScanning()
                    }
                    .foregroundColor(.secondary)
                } else {
                    Button {
                        connectionVM.startScanning()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
        }
        .onAppear {
            if connectionVM.status == .disconnected {
                connectionVM.startScanning()
            }
        }
    }

    // MARK: - Transport Picker Section

    private var transportPickerSection: some View {
        VStack(spacing: 8) {
            Picker("Transport Mode", selection: $connectionVM.connectionType) {
                Label("Bluetooth LE", systemImage: "antenna.radiowaves.left.and.right")
                    .tag(ConnectionType.bluetooth)

                Label("Wi-Fi TCP", systemImage: "wifi")
                    .tag(ConnectionType.wifi)
            }
            .pickerStyle(.segmented)
            .onChange(of: connectionVM.connectionType) { newType in
                connectionVM.startScanning(type: newType)
            }
        }
    }

    // MARK: - Connected Device Card

    private func connectedDeviceCard(device: DeviceInfo) -> some View {
        VStack(spacing: 16) {
            // Header Row: Device Name & Status
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0x2ECC71).opacity(0.18))
                        .frame(width: 48, height: 48)

                    Image(systemName: device.connectionType.symbolName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(hex: 0x2ECC71))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Circle()
                            .fill(Color(hex: 0x2ECC71))
                            .frame(width: 8, height: 8)
                    }

                    Text("\(device.connectionType.displayName) • Connected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Disconnect Button
                Button {
                    connectionVM.disconnect()
                } label: {
                    Text("Disconnect")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: 0xE74C3C))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(hex: 0xE74C3C).opacity(0.15))
                        )
                }
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Metrics Telemetry Grid (Latency, Signal, Uptime, Loss)
            HStack(spacing: 0) {
                metricCell(
                    title: "LATENCY",
                    value: String(format: "%.1f ms", connectionVM.metrics.latency),
                    icon: "speedometer",
                    tint: latencyColor(connectionVM.metrics.latency)
                )

                Divider()
                    .frame(height: 36)
                    .background(Color.white.opacity(0.1))

                metricCell(
                    title: "SIGNAL",
                    value: device.formattedSignalStrength,
                    icon: "chart.bar.fill",
                    tint: Color(hex: 0x2ECC71)
                )

                Divider()
                    .frame(height: 36)
                    .background(Color.white.opacity(0.1))

                metricCell(
                    title: "UPTIME",
                    value: formatUptime(connectionVM.metrics.connectionUptime),
                    icon: "clock.fill",
                    tint: Color(hex: 0x00FFCC)
                )

                Divider()
                    .frame(height: 36)
                    .background(Color.white.opacity(0.1))

                metricCell(
                    title: "PACKETS",
                    value: "\(connectionVM.metrics.packetsSent)",
                    icon: "arrow.up.arrow.down",
                    tint: .white
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(hex: 0x2ECC71).opacity(0.4), lineWidth: 1.2)
                )
        )
    }

    private func metricCell(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)

            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(tint)

                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scanning Status Bar

    private var scanningStatusBar: some View {
        HStack(spacing: 10) {
            if connectionVM.status == .scanning {
                ZStack {
                    Circle()
                        .stroke(Color(hex: 0x2A75D3).opacity(0.3), lineWidth: 2)
                        .scaleEffect(radarPulse ? 1.6 : 0.8)
                        .opacity(radarPulse ? 0.0 : 1.0)
                        .frame(width: 20, height: 20)

                    Circle()
                        .fill(Color(hex: 0x2A75D3))
                        .frame(width: 8, height: 8)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        radarPulse = true
                    }
                }

                Text("Scanning for \(connectionVM.connectionType.displayName) devices...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                ProgressView()
                    .scaleEffect(0.8)
            } else if connectionVM.status == .connecting {
                ProgressView()
                    .scaleEffect(0.8)

                Text("Establishing secure connection...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: 0xF1C40F))

                Spacer()
            } else if let error = connectionVM.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: 0xE74C3C))
                    .font(.system(size: 14))

                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: 0xE74C3C))
                    .lineLimit(2)

                Spacer()
            } else {
                Text("Ready to scan")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Scan Now") {
                    connectionVM.startScanning()
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: 0x2A75D3))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.10))
        )
    }

    // MARK: - Discovered Devices Section

    private var discoveredDevicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DISCOVERED COMPANIONS")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(connectionVM.discoveredDevices.count) found")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            if connectionVM.discoveredDevices.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 8) {
                    ForEach(connectionVM.discoveredDevices) { device in
                        deviceRow(device: device)
                    }
                }
            }
        }
    }

    private func deviceRow(device: DeviceInfo) -> some View {
        let isCurrent = connectionVM.selectedDevice?.id == device.id && connectionVM.status == .connected
        let isConnectingThis = connectionVM.selectedDevice?.id == device.id && connectionVM.status == .connecting

        return HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCurrent ? Color(hex: 0x2ECC71).opacity(0.2) : Color(white: 0.16))
                    .frame(width: 40, height: 40)

                Image(systemName: device.connectionType.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isCurrent ? Color(hex: 0x2ECC71) : .white)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(device.formattedSignalStrength)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)

                    if let lastSeen = device.lastConnected {
                        Text("• Seen \(lastSeen, style: .time)")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Connect / Connected Action
            if isCurrent {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Active")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Color(hex: 0x2ECC71))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(hex: 0x2ECC71).opacity(0.12)))
            } else if isConnectingThis {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.horizontal, 14)
            } else {
                Button {
                    connectionVM.connect(to: device)
                } label: {
                    Text("Connect")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: 0x2A75D3), Color(hex: 0x1E5BB5)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isCurrent ? Color(hex: 0x2ECC71).opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: connectionVM.connectionType == .bluetooth ? "antenna.radiowaves.left.and.right.slash" : "wifi.slash")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Text("No Companion Devices Found")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Text("Make sure the VNTM Gamepad Windows companion app is running and your PC is advertising on \(connectionVM.connectionType.displayName).")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                connectionVM.startScanning()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Search Again")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: 0x2A75D3))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(hex: 0x2A75D3).opacity(0.15)))
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.04), lineWidth: 1))
        )
    }

    // MARK: - Manual Wi-Fi Entry Section

    private var manualWiFiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isShowingManualEntry.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(Color(hex: 0x2A75D3))
                    Text("Direct Wi-Fi TCP Connection")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: isShowingManualEntry ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.11)))
            }

            if isShowingManualEntry {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        // IP Host Field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Host IPv4 / Hostname")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)

                            TextField("192.168.1.100", text: $manualHost)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.07)))
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .keyboardType(.numbersAndPunctuation)
                        }

                        // Port Field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Port")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)

                            TextField("7777", text: $manualPort)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.07)))
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                        }
                    }

                    // Direct Connect Button
                    Button {
                        connectToManualTarget()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                            Text("Connect via Direct IP")
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: 0x2ECC71), Color(hex: 0x27AE60)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(10)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(white: 0.09))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
                )
            }
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SESSION RECOVERY")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Toggle(isOn: $connectionVM.isAutoReconnect) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Reconnect")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Automatically retry dropped connections using exponential backoff (1s - 30s).")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.11))
            )
        }
    }

    // MARK: - Action Helpers

    private func connectToManualTarget() {
        let cleanHost = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHost = cleanHost.isEmpty ? "192.168.1.100" : cleanHost
        let portVal = UInt16(manualPort) ?? WiFiService.defaultPort

        let device = DeviceInfo(
            id: "\(resolvedHost):\(portVal)",
            name: "PC (\(resolvedHost))",
            connectionType: .wifi
        )

        connectionVM.connect(to: device)
    }

    private func latencyColor(_ latency: Double) -> Color {
        if latency <= 0 { return .secondary }
        if latency < 15.0 { return Color(hex: 0x2ECC71) } // Green
        if latency < 30.0 { return Color(hex: 0xF1C40F) } // Yellow
        return Color(hex: 0xE74C3C) // Red
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let mins = (total % 3600) / 60
        let secs = total % 60
        if total >= 3600 {
            let hours = total / 3600
            return String(format: "%02d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}

#if DEBUG
struct ConnectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ConnectionView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
