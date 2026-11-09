//
//  ConnectionStatusBar.swift
//  VNTM Gamepad
//
//  A compact top status bar displaying real-time transport connectivity,
//  signal quality, animated connection states, and color-coded latency metrics.
//

import SwiftUI

// MARK: - ConnectionStatus Visual Presentation Extensions

extension ConnectionStatus {
    /// SF Symbol icon associated with the connection lifecycle state.
    public var sfSymbol: String {
        switch self {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting, .scanning:
            return "arrow.triangle.2.circlepath"
        case .disconnected:
            return "slash.circle"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    /// Characteristic accent color matching Apple Human Interface Guidelines and gaming HUDs.
    public var themeColor: Color {
        switch self {
        case .connected:
            return Color(hex: 0x2ECC71) // Green (connected)
        case .connecting, .scanning:
            return Color(hex: 0xF1C40F) // Yellow (connecting)
        case .disconnected:
            return Color(hex: 0x95A5A6) // Gray (disconnected)
        case .error:
            return Color(hex: 0xE74C3C) // Red (error)
        }
    }
}

// MARK: - ConnectionStatusBar View

/// A compact, high-visibility status bar for virtual gamepad navigation headers.
///
/// Displays connection icon, status label, signal strength meter, and color-coded latency badge.
public struct ConnectionStatusBar: View {
    // MARK: - Properties

    let status: ConnectionStatus
    let latencyMs: Double?
    let signalBars: Int // 0 to 4
    let transportName: String?
    let onTap: (() -> Void)?

    // MARK: - State

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.5

    // MARK: - Initialization

    /// Creates a connection status bar.
    /// - Parameters:
    ///   - status: Current connection lifecycle state (connected, connecting, disconnected, error).
    ///   - latencyMs: Round-trip latency in milliseconds, or nil if disconnected.
    ///   - signalBars: Signal quality from 0 (none) to 4 (maximum). Defaults to 4 when connected.
    ///   - transportName: Optional transport label (e.g. "Bluetooth", "Wi-Fi").
    ///   - onTap: Optional tap handler for opening connection settings or retry.
    public init(
        status: ConnectionStatus = .disconnected,
        latencyMs: Double? = nil,
        signalBars: Int = 4,
        transportName: String? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.status = status
        self.latencyMs = latencyMs
        self.signalBars = max(0, min(4, signalBars))
        self.transportName = transportName
        self.onTap = onTap
    }

    /// Convenience initializer integrating with project ConnectionMetrics and ConnectionType.
    public init(
        status: ConnectionStatus,
        metrics: ConnectionMetrics,
        connectionType: ConnectionType? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.status = status
        self.latencyMs = (status == .connected && metrics.latency > 0) ? metrics.latency : nil
        let calculatedBars: Int
        if status == .connected {
            calculatedBars = metrics.signalStrength > 0 ? min(4, max(1, metrics.signalStrength / 25)) : 4
        } else {
            calculatedBars = 0
        }
        self.signalBars = calculatedBars
        self.transportName = connectionType?.rawValue.capitalized
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 10) {
            // MARK: Status Icon (pulsing when connecting/scanning)
            statusIconView

            // MARK: Status Text & Transport Name
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(status.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(status.themeColor)
                        .lineLimit(1)

                    if let transportName = transportName, status == .connected {
                        Text("• \(transportName)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            // MARK: Signal Strength Bars
            if status == .connected || status == .connecting {
                signalStrengthBars
            }

            // MARK: Latency Badge
            latencyBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.panelCornerRadius, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.panelCornerRadius, style: .continuous)
                .stroke(status.themeColor.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            updatePulseAnimation()
        }
        .onChange(of: status) { _ in
            updatePulseAnimation()
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: status)
        // Accessibility
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Connection Status"))
        .accessibilityValue(Text(accessibilityStatusDescription))
    }

    // MARK: - Status Icon Subview

    private var statusIconView: some View {
        ZStack {
            // Pulse ring during connection negotiation
            if status == .connecting || status == .scanning {
                Circle()
                    .stroke(status.themeColor.opacity(pulseOpacity), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .scaleEffect(pulseScale)
            }

            Image(systemName: status.sfSymbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(status.themeColor)
                .rotationEffect(
                    (status == .connecting || status == .scanning)
                        ? .degrees(pulseScale > 1.1 ? 180 : 0)
                        : .zero
                )
        }
        .frame(width: 22, height: 22)
    }

    // MARK: - Signal Strength Subview

    private var signalStrengthBars: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(1...4, id: \.self) { barIndex in
                let barHeight = CGFloat(4 + barIndex * 3)
                let isFilled = barIndex <= signalBars

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isFilled ? status.themeColor : Color.white.opacity(0.18))
                    .frame(width: 3.5, height: barHeight)
            }
        }
        .frame(height: 16)
        .accessibilityLabel(Text("Signal strength: \(signalBars) of 4 bars"))
    }

    // MARK: - Latency Badge

    private var latencyBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(latencyColor)
                .frame(width: 6, height: 6)

            Text(latencyText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(latencyColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(
            Capsule()
                .fill(latencyColor.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(latencyColor.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Latency Math & Styling

    private var latencyColor: Color {
        guard status == .connected, let ms = latencyMs else {
            return Color.gray
        }

        // Color coding: <15ms green, <30ms yellow, >30ms red
        if ms < 15.0 {
            return Color(hex: 0x2ECC71) // Green: <15ms
        } else if ms < 30.0 {
            return Color(hex: 0xF1C40F) // Yellow: <30ms
        } else {
            return Color(hex: 0xE74C3C) // Red: >30ms
        }
    }

    private var latencyText: String {
        guard status == .connected, let ms = latencyMs else {
            return "-- ms"
        }
        return String(format: "%.0f ms", ms)
    }

    // MARK: - Animations

    private func updatePulseAnimation() {
        if status == .connecting || status == .scanning {
            withAnimation(
                .easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.35
                pulseOpacity = 0.0
            }
        } else {
            pulseScale = 1.0
            pulseOpacity = 0.5
        }
    }

    private var accessibilityStatusDescription: String {
        var desc = status.displayName
        if let ms = latencyMs, status == .connected {
            desc += ", latency \(Int(ms)) milliseconds"
        }
        desc += ", signal \(signalBars) of 4 bars"
        return desc
    }
}

// MARK: - Previews

#if DEBUG
struct ConnectionStatusBar_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()

            VStack(spacing: 16) {
                // Connected, low latency (<15ms)
                ConnectionStatusBar(
                    status: .connected,
                    latencyMs: 8.5,
                    signalBars: 4,
                    transportName: "Wi-Fi"
                )

                // Connected, medium latency (<30ms)
                ConnectionStatusBar(
                    status: .connected,
                    latencyMs: 24.0,
                    signalBars: 3,
                    transportName: "Bluetooth"
                )

                // Connected, high latency (>30ms)
                ConnectionStatusBar(
                    status: .connected,
                    latencyMs: 46.2,
                    signalBars: 1,
                    transportName: "Bluetooth"
                )

                // Connecting
                ConnectionStatusBar(
                    status: .connecting,
                    latencyMs: nil,
                    signalBars: 2
                )

                // Disconnected
                ConnectionStatusBar(
                    status: .disconnected,
                    latencyMs: nil,
                    signalBars: 0
                )

                // Error
                ConnectionStatusBar(
                    status: .error,
                    latencyMs: nil,
                    signalBars: 0
                )
            }
            .padding()
        }
    }
}
#endif
