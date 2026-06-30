//
//  GyroMouseManager.swift
//  KeyMod
//
//  CoreMotion device tilt → mouse movement. Uses gyroscope + accelerometer
//  to map roll/pitch angles to cursor displacement.
//

import CoreMotion
import Foundation

@MainActor
class GyroMouseManager: ObservableObject {

    // MARK: - Published State

    @Published var isEnabled = false
    @Published var sensitivity: Double = 1.0
    @Published var isCalibrating = false
    @Published var offsetX: Double = 0
    @Published var offsetY: Double = 0

    // MARK: - Configuration

    /// Dead-zone threshold (radians). Motion below this is ignored.
    var deadZone: Double = 0.02

    /// Maximum rotation rate (rad/s) mapped to full mouse velocity.
    var maxRate: Double = 2.0

    /// Update interval in seconds (1/60 ≈ 0.0167 for 60 Hz).
    var updateInterval: TimeInterval = 1.0 / 60.0

    /// Mouse cursor sensitivity multiplier applied to angular velocity.
    var cursorSensitivity: Double = 300.0

    // MARK: - Private State

    private let motionManager = CMMotionManager()
    private weak var mouseManager: MouseManager?
    private var baselineGyroX: Double = 0
    private var baselineGyroY: Double = 0
    private var isRunning = false

    // MARK: - Init

    init(mouseManager: MouseManager? = nil) {
        self.mouseManager = mouseManager
    }

    // MARK: - Public API

    func setMouseManager(_ manager: MouseManager?) {
        self.mouseManager = manager
    }

    func start() {
        guard !isRunning else { return }
        guard motionManager.isGyroAvailable || motionManager.isDeviceMotionAvailable else {
            LogManager.shared.log("GyroMouseManager: No motion sensors available", category: "Gyro", level: .warning)
            return
        }

        isRunning = true
        calibrate()

        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = updateInterval
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical,
                                                   to: .main) { [weak self] motion, error in
                guard let self = self, self.isEnabled else { return }
                if let error = error {
                    LogManager.shared.log("GyroMouseManager: Device motion error: \(error.localizedDescription)", category: "Gyro", level: .warning)
                    return
                }
                guard let motion = motion else { return }
                self.processDeviceMotion(motion)
            }
        } else if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = updateInterval
            motionManager.startGyroUpdates(to: .main) { [weak self] gyroData, error in
                guard let self = self, self.isEnabled else { return }
                if let error = error {
                    LogManager.shared.log("GyroMouseManager: Gyro error: \(error.localizedDescription)", category: "Gyro", level: .warning)
                    return
                }
                guard let gyroData = gyroData else { return }
                self.processGyroOnly(gyroData)
            }
        }
    }

    func stop() {
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopGyroUpdates()
        offsetX = 0
        offsetY = 0
    }

    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }

    func enable() {
        isEnabled = true
        if isRunning { return }
        start()
    }

    func disable() {
        isEnabled = false
    }

    func calibrate() {
        guard motionManager.isDeviceMotionAvailable else { return }
        isCalibrating = true

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion else { return }
            self?.baselineGyroX = motion.rotationRate.x
            self?.baselineGyroY = motion.rotationRate.y
            self?.motionManager.stopDeviceMotionUpdates()
            self?.isCalibrating = false
            LogManager.shared.log("GyroMouseManager: Calibrated baseline X=\(self?.baselineGyroX ?? 0) Y=\(self?.baselineGyroY ?? 0)", category: "Gyro")
        }
    }

    // MARK: - Motion Processing

    private func processDeviceMotion(_ motion: CMDeviceMotion) {
        let rawRateX = motion.rotationRate.x - baselineGyroX
        let rawRateY = motion.rotationRate.y - baselineGyroY

        let rateX = applyDeadZone(rawRateX)
        let rateY = applyDeadZone(rawRateY)

        let clampedX = clampRate(rateX)
        let clampedY = clampRate(rateY)

        let dx = clampedX * cursorSensitivity * sensitivity
        let dy = -clampedY * cursorSensitivity * sensitivity

        let boundedX = clampMouseDelta(dx)
        let boundedY = clampMouseDelta(dy)

        sendMouseMovement(dx: boundedX, dy: boundedY)
    }

    private func processGyroOnly(_ gyroData: CMGyroData) {
        let rawRateX = gyroData.rotationRate.x - baselineGyroX
        let rawRateY = gyroData.rotationRate.y - baselineGyroY

        let rateX = applyDeadZone(rawRateX)
        let rateY = applyDeadZone(rawRateY)

        let clampedX = clampRate(rateX)
        let clampedY = clampRate(rateY)

        let dx = clampedX * cursorSensitivity * sensitivity
        let dy = -clampedY * cursorSensitivity * sensitivity

        let boundedX = clampMouseDelta(dx)
        let boundedY = clampMouseDelta(dy)

        sendMouseMovement(dx: boundedX, dy: boundedY)
    }

    private func applyDeadZone(_ rate: Double) -> Double {
        abs(rate) < deadZone ? 0 : rate
    }

    private func clampRate(_ rate: Double) -> Double {
        max(-maxRate, min(maxRate, rate)) / maxRate
    }

    private func clampMouseDelta(_ value: Double) -> Int {
        Int(max(-127, min(127, value)))
    }

    private func sendMouseMovement(dx: Int, dy: Int) {
        guard dx != 0 || dy != 0 else { return }
        guard let mouseManager = mouseManager else { return }
        let boundedX = Int8(max(-127, min(127, dx)))
        let boundedY = Int8(max(-127, min(127, dy)))
        let packet = Keymod.buildMouseRel(buttons: 0x00, dx: boundedX, dy: boundedY, wheel: 0)
        mouseManager.bleManager.sendTouchData(data: packet)
    }
}
