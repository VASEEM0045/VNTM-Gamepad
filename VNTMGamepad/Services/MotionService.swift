//
//  MotionService.swift
//  VNTM Gamepad
//
//  CoreMotion device attitude and acceleration sensor pipeline.
//  Provides high-frequency 6-DoF motion tracking, calibration offset storage,
//  and throttled delivery for gyro steering and motion controls.
//

import Foundation
import CoreMotion
import Combine
import os.log

/// Calibration offsets subtracted from raw sensor measurements.
public struct MotionCalibrationOffsets: Codable, Equatable {
    public var pitch: Double = 0.0
    public var roll: Double = 0.0
    public var yaw: Double = 0.0
    public var accelX: Double = 0.0
    public var accelY: Double = 0.0
    public var accelZ: Double = 0.0

    public init(pitch: Double = 0.0,
                roll: Double = 0.0,
                yaw: Double = 0.0,
                accelX: Double = 0.0,
                accelY: Double = 0.0,
                accelZ: Double = 0.0) {
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.accelX = accelX
        self.accelY = accelY
        self.accelZ = accelZ
    }
}

/// Service managing device motion sensors for steering and motion-based gameplay.
///
/// Captures device attitude (pitch, roll, yaw) and user acceleration (x, y, z),
/// applies zero-point calibration, and publishes smoothed values at configurable rates.
public final class MotionService: ObservableObject {

    // MARK: - Constants

    /// Key for persisting motion calibration offsets in UserDefaults.
    private static let calibrationKey = "vntm.motion.calibrationOffsets"

    // MARK: - Published Properties

    /// Whether device motion hardware (gyroscope + accelerometer) is available.
    @Published public private(set) var isAvailable: Bool = false

    /// Calibrated pitch angle (tilt front-back) in radians.
    @Published public private(set) var pitch: Double = 0.0

    /// Calibrated roll angle (tilt left-right) in radians.
    @Published public private(set) var roll: Double = 0.0

    /// Calibrated yaw angle (rotation around vertical axis) in radians.
    @Published public private(set) var yaw: Double = 0.0

    /// Calibrated linear acceleration along the X-axis (G's).
    @Published public private(set) var accelerationX: Double = 0.0

    /// Calibrated linear acceleration along the Y-axis (G's).
    @Published public private(set) var accelerationY: Double = 0.0

    /// Calibrated linear acceleration along the Z-axis (G's).
    @Published public private(set) var accelerationZ: Double = 0.0

    /// Whether sensor updates are currently running.
    @Published public private(set) var isActive: Bool = false

    // MARK: - Private Properties

    /// CoreMotion hardware manager.
    private let motionManager = CMMotionManager()

    /// Background operation queue for sensor sampling.
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.vntm.gamepad.motion.queue"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    /// Stored zero-point calibration offsets.
    public private(set) var calibrationOffsets: MotionCalibrationOffsets

    /// Last observed raw sensor readings used for instantaneous calibration.
    private var lastRawPitch: Double = 0.0
    private var lastRawRoll: Double = 0.0
    private var lastRawYaw: Double = 0.0
    private var lastRawAccelX: Double = 0.0
    private var lastRawAccelY: Double = 0.0
    private var lastRawAccelZ: Double = 0.0

    /// Key-value storage for settings.
    private let userDefaults: UserDefaults

    /// Native unified logger.
    private let logger = Logger(subsystem: "com.vntm.gamepad", category: "Motion")

    // MARK: - Initialization

    /// Initializes a new MotionService instance.
    /// - Parameter userDefaults: Key-value storage (defaults to `.standard`).
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load persisted calibration offsets if available
        if let data = userDefaults.data(forKey: Self.calibrationKey),
           let offsets = try? JSONDecoder().decode(MotionCalibrationOffsets.self, from: data) {
            self.calibrationOffsets = offsets
        } else {
            self.calibrationOffsets = MotionCalibrationOffsets()
        }

        self.isAvailable = motionManager.isDeviceMotionAvailable
        AppLog.info("MotionService initialized. Hardware available: \(self.isAvailable)", category: .motion)
    }

    deinit {
        stopUpdates()
    }

    // MARK: - Public API

    /// Starts streaming device motion updates at the specified sampling interval.
    /// - Parameter interval: Update interval in seconds (defaults to 1.0 / 60.0, or 60 Hz).
    public func startUpdates(interval: TimeInterval = 1.0 / 60.0) {
        guard motionManager.isDeviceMotionAvailable else {
            logger.error("Cannot start motion updates: Device motion is not available on this device.")
            AppLog.error("Motion sensors unavailable.", category: .motion)
            isAvailable = false
            return
        }

        guard !isActive else {
            logger.debug("Motion updates already running.")
            return
        }

        motionManager.deviceMotionUpdateInterval = interval
        logger.info("Starting device motion updates at \(1.0 / interval, format: .fixed(precision: 1)) Hz...")
        AppLog.info("Starting motion updates (\(Int(1.0 / interval)) Hz)...", category: .motion)

        // Prefer arbitrary reference frame with vertical Z axis
        let referenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical

        motionManager.startDeviceMotionUpdates(using: referenceFrame, to: motionQueue) { [weak self] motion, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Motion update error: \(error.localizedDescription)")
                AppLog.error("Motion sensor error: \(error.localizedDescription)", category: .motion)
                return
            }

            guard let motion = motion else { return }

            // Cache raw readings for zero-point calibration
            self.lastRawPitch = motion.attitude.pitch
            self.lastRawRoll = motion.attitude.roll
            self.lastRawYaw = motion.attitude.yaw
            self.lastRawAccelX = motion.userAcceleration.x
            self.lastRawAccelY = motion.userAcceleration.y
            self.lastRawAccelZ = motion.userAcceleration.z

            // Apply calibration offsets
            let calibratedPitch = self.lastRawPitch - self.calibrationOffsets.pitch
            let calibratedRoll = self.lastRawRoll - self.calibrationOffsets.roll
            let calibratedYaw = self.lastRawYaw - self.calibrationOffsets.yaw

            let calibratedAccX = self.lastRawAccelX - self.calibrationOffsets.accelX
            let calibratedAccY = self.lastRawAccelY - self.calibrationOffsets.accelY
            let calibratedAccZ = self.lastRawAccelZ - self.calibrationOffsets.accelZ

            DispatchQueue.main.async {
                self.pitch = calibratedPitch
                self.roll = calibratedRoll
                self.yaw = calibratedYaw
                self.accelerationX = calibratedAccX
                self.accelerationY = calibratedAccY
                self.accelerationZ = calibratedAccZ
            }
        }

        isActive = true
    }

    /// Stops device motion sensor updates.
    public func stopUpdates() {
        guard isActive else { return }

        logger.info("Stopping device motion updates.")
        AppLog.info("Stopped motion updates.", category: .motion)

        motionManager.stopDeviceMotionUpdates()
        isActive = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pitch = 0.0
            self.roll = 0.0
            self.yaw = 0.0
            self.accelerationX = 0.0
            self.accelerationY = 0.0
            self.accelerationZ = 0.0
        }
    }

    /// Calibrates the motion sensors by adopting current orientation and acceleration as the new zero point.
    public func calibrate() {
        let newOffsets = MotionCalibrationOffsets(
            pitch: lastRawPitch,
            roll: lastRawRoll,
            yaw: lastRawYaw,
            accelX: lastRawAccelX,
            accelY: lastRawAccelY,
            accelZ: lastRawAccelZ
        )
        self.calibrationOffsets = newOffsets

        // Persist new calibration
        if let encoded = try? JSONEncoder().encode(newOffsets) {
            userDefaults.set(encoded, forKey: Self.calibrationKey)
        }

        logger.info("Motion calibrated. Offsets -> Pitch: \(newOffsets.pitch, format: .fixed(precision: 3)), Roll: \(newOffsets.roll, format: .fixed(precision: 3)), Yaw: \(newOffsets.yaw, format: .fixed(precision: 3))")
        AppLog.info("Motion sensors calibrated to neutral orientation.", category: .motion)

        DispatchQueue.main.async { [weak self] in
            self?.pitch = 0.0
            self?.roll = 0.0
            self?.yaw = 0.0
            self?.accelerationX = 0.0
            self?.accelerationY = 0.0
            self?.accelerationZ = 0.0
        }
    }

    /// Resets calibration offsets back to zero.
    public func resetCalibration() {
        calibrationOffsets = MotionCalibrationOffsets()
        userDefaults.removeObject(forKey: Self.calibrationKey)
        logger.info("Motion calibration reset to identity.")
        AppLog.info("Motion calibration reset.", category: .motion)
    }
}
