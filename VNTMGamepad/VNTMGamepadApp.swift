//
//  VNTMGamepadApp.swift
//  VNTM Gamepad
//  Bundle ID: com.vntm.gamepad
//
//  Created for iOS 15.0+
//  MVVM Architecture with Combine Framework
//

import SwiftUI

/// Main entry point for the VNTM Gamepad iOS application.
///
/// Orchestrates the dependency graph by instantiating core infrastructure services
/// (Bluetooth LE, Wi-Fi TCP, CoreHaptics, CoreMotion, Profile persistence)
/// and injecting them into the ViewModels, while binding app lifecycle transitions
/// to pause high-frequency transmission or sensor polling when backgrounded.
@main
struct VNTMGamepadApp: App {

    // MARK: - Scene Lifecycle

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Core Services

    private let bluetoothService: BluetoothService
    private let wiFiService: WiFiService
    private let hapticService: HapticService
    private let motionService: MotionService
    private let profileService: ProfileService

    // MARK: - ViewModels (Injected as Environment Objects)

    @StateObject private var controllerVM: GameControllerViewModel
    @StateObject private var connectionVM: ConnectionViewModel
    @StateObject private var settingsVM: SettingsViewModel

    // MARK: - Initialization

    init() {
        // 1. Initialize core background transport & sensor services
        let bt = BluetoothService()
        let wifi = WiFiService()
        let haptics = HapticService()
        let motion = MotionService()
        let profiles = ProfileService()

        self.bluetoothService = bt
        self.wiFiService = wifi
        self.hapticService = haptics
        self.motionService = motion
        self.profileService = profiles

        // 2. Initialize ViewModels with injected service dependencies
        _controllerVM = StateObject(wrappedValue: GameControllerViewModel(
            bluetoothService: bt,
            wiFiService: wifi,
            hapticService: haptics,
            motionService: motion,
            profileService: profiles
        ))

        _connectionVM = StateObject(wrappedValue: ConnectionViewModel(
            bluetoothService: bt,
            wiFiService: wifi
        ))

        _settingsVM = StateObject(wrappedValue: SettingsViewModel(
            profileService: profiles,
            hapticService: haptics
        ))

        // 3. Configure global UI appearances for dark gaming aesthetic
        configureGlobalAppearance()
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(controllerVM)
                .environmentObject(connectionVM)
                .environmentObject(settingsVM)
                .preferredColorScheme(resolvedColorScheme)
                .onAppear {
                    // Prepare CoreHaptics engine when app window opens
                    hapticService.prepareEngine()
                }
        }
        .onChange(of: scenePhase) { newPhase in
            handleScenePhaseTransition(newPhase)
        }
    }

    // MARK: - Scene Phase Lifecycle Handling

    private func handleScenePhaseTransition(_ phase: ScenePhase) {
        switch phase {
        case .active:
            AppLog.info("Application became active. Resuming session.", category: .general)
            hapticService.prepareEngine()

            // If auto-reconnect is enabled and currently disconnected, attempt resume
            if connectionVM.isAutoReconnect && connectionVM.status == .disconnected {
                connectionVM.startScanning()
            }

        case .inactive:
            AppLog.debug("Application transitioned to inactive.", category: .general)

        case .background:
            AppLog.info("Application entered background. Releasing pressed inputs.", category: .general)

            // Safely release digital inputs to prevent stuck keys on PC host
            controllerVM.controllerState.releaseAll()

            // Stop gyroscopic motion updates to preserve battery
            if motionService.isActive {
                motionService.stopUpdates()
            }

        @unknown default:
            break
        }
    }

    // MARK: - Color Scheme & Global Appearance

    private var resolvedColorScheme: ColorScheme? {
        switch settingsVM.selectedTheme {
        case .light:
            return .light
        case .dark, .neon, .midnight, .custom:
            return .dark
        }
    }

    private func configureGlobalAppearance() {
        // Dark navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1.0)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance

        // Dark tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1.0)

        UITabBar.appearance().standardAppearance = tabBarAppearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }
    }
}
