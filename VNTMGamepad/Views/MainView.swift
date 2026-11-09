//
//  MainView.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//  MVVM Architecture with Combine Framework
//

import SwiftUI

/// The root navigation and tab container for the VNTM Gamepad application.
///
/// Houses three primary workflow tabs:
/// 1. **Controller**: Low-latency landscape game controller interface.
/// 2. **Connection**: Bluetooth LE & local Wi-Fi pairing and diagnostic monitor.
/// 3. **Settings**: Profile configuration, sensitivity curves, and calibration.
public struct MainView: View {

    // MARK: - Injected ViewModels

    @EnvironmentObject private var controllerVM: GameControllerViewModel
    @EnvironmentObject private var connectionVM: ConnectionViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    // MARK: - State

    @State private var selectedTab: Int = 0

    // MARK: - Initialization

    public init() {}

    // MARK: - Body

    public var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: Tab 1 - Controller
            ControllerView()
                .tabItem {
                    Label("Controller", systemImage: "gamecontroller.fill")
                }
                .tag(0)

            // MARK: Tab 2 - Connection
            NavigationView {
                ConnectionView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Connection", systemImage: "wifi")
            }
            .tag(1)
            .badge(connectionBadge)

            // MARK: Tab 3 - Settings
            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
        .accentColor(themeAccentColor)
        // Calibration modal sheet triggered by controllerVM.showCalibration
        .sheet(isPresented: $controllerVM.showCalibration) {
            NavigationView {
                CalibrationView()
            }
            .navigationViewStyle(.stack)
            .accentColor(themeAccentColor)
        }
        // First-launch onboarding modal sheet
        .sheet(isPresented: $settingsVM.showOnboarding) {
            OnboardingView()
                .environmentObject(settingsVM)
                .accentColor(themeAccentColor)
        }
    }

    // MARK: - Badges & Status

    /// Displays an attention badge on the Connection tab when the gamepad is disconnected.
    private var connectionBadge: String? {
        switch connectionVM.status {
        case .disconnected:
            return "!"
        case .error:
            return "ERR"
        case .connecting, .scanning:
            return "..."
        case .connected:
            return nil
        }
    }

    /// Dynamic theme accent color matching the user's active theme profile.
    private var themeAccentColor: Color {
        switch settingsVM.selectedTheme {
        case .light:
            return Color.blue
        case .dark:
            return Color(hex: 0x2A75D3)
        case .neon:
            return Color(hex: 0x00FFCC)
        case .midnight:
            return Color(hex: 0x00E5FF)
        case .custom:
            return Color(hex: 0x5856D6)
        }
    }
}

// MARK: - Onboarding View

/// A modern welcome and introductory sheet presented on initial app launch.
private struct OnboardingView: View {
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: 0x0D1117)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Icon & Glow
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: 0x2A75D3).opacity(0.4), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 70
                            )
                        )
                        .frame(width: 140, height: 140)

                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(.white)
                }

                // Title & Subtitle
                VStack(spacing: 8) {
                    Text("Welcome to VNTM Gamepad")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Turn your iPhone into an ultra-low latency wireless controller for PC gaming.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Feature Highlights
                VStack(spacing: 16) {
                    FeatureRow(
                        icon: "wifi",
                        title: "Dual Wireless Transport",
                        subtitle: "Seamlessly stream via Bluetooth LE or ultra-fast local Wi-Fi TCP."
                    )
                    FeatureRow(
                        icon: "slider.horizontal.3",
                        title: "Modular Layouts",
                        subtitle: "Switch between Classic Xbox, Arcade Fightstick, and Racing Wheel."
                    )
                    FeatureRow(
                        icon: "waveform",
                        title: "Haptic Feedback",
                        subtitle: "Experience realistic tactile resistance and button click vibrations."
                    )
                }
                .padding(.horizontal, 20)

                Spacer()

                // Continue Button
                Button {
                    settingsVM.completeOnboarding()
                    dismiss()
                } label: {
                    Text("Get Started")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: 0x2A75D3), Color(hex: 0x1E5BB5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: Color(hex: 0x2A75D3).opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .padding()
        }
    }
}

// MARK: - Feature Row Helper

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.14))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(hex: 0x2A75D3))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
    }
}

#if DEBUG
struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .preferredColorScheme(.dark)
    }
}
#endif
