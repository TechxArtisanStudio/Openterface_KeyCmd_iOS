//
//  HapticFeedbackManager.swift
//  KeyMod
//
//  Created by System on 2025/7/19.
//

import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

class HapticFeedbackManager: ObservableObject {
    static let shared = HapticFeedbackManager()

    @Published var isHapticEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHapticEnabled, forKey: "hapticFeedbackEnabled")
        }
    }

    #if os(iOS)
    // Keep strong reference to prevent immediate deallocation
    private var scrollGenerator: UIImpactFeedbackGenerator?
    private var lastHapticTime: Date = .distantPast

    // MARK: - Device Diagnostics

    /// Check if the device has a Taptic Engine (iPhone 7 and later, excluding iPhone SE 1st gen)
    var hasTapticEngine: Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        // Devices without Taptic Engine:
        // - iPhone 6s and earlier
        // - iPhone SE (1st generation)
        // - iPod Touch (all models)
        // - iPad (all models)
        let noTapticDevices = [
            "iPhone6,1", "iPhone6,2",  // iPhone 5s
            "iPhone7,1", "iPhone7,2",  // iPhone 6 Plus, 6
            "iPhone8,1", "iPhone8,2", "iPhone8,4",  // iPhone 6s Plus, 6s, SE (1st gen)
            "iPod"  // All iPod Touch models
        ]

        // Check if it's an iPad or iPod
        if identifier.hasPrefix("iPad") || identifier.hasPrefix("iPod") {
            return false
        }

        // Check if it's an iPhone model without Taptic Engine
        if noTapticDevices.contains(identifier) {
            return false
        }

        return true
    }

    /// Get the device model name for display
    var deviceModelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        // Map device identifiers to friendly names
        let modelMap: [String: String] = [
            "iPhone9,1": "iPhone 7", "iPhone9,2": "iPhone 7 Plus",
            "iPhone9,3": "iPhone 7", "iPhone9,4": "iPhone 7 Plus",
            "iPhone10,1": "iPhone 8", "iPhone10,2": "iPhone 8 Plus",
            "iPhone10,4": "iPhone 8", "iPhone10,5": "iPhone 8 Plus",
            "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
            "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max",
            "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
            "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            "iPhone12,8": "iPhone SE (2nd generation)",
            "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,6": "iPhone SE (3rd generation)",
            "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max"
        ]

        return modelMap[identifier] ?? "Unknown Device (\(identifier))"
    }

    /// Check if the device is in Low Power Mode
    var isLowPowerModeEnabled: Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Get diagnostic information as a formatted string
    var diagnosticInfo: String {
        var info = "Device: \(deviceModelName)\n"
        info += "Taptic Engine: \(hasTapticEngine ? "✅ Available" : "❌ Not Available")\n"
        info += "Low Power Mode: \(isLowPowerModeEnabled ? "⚠️ ON (reduces haptics)" : "✅ OFF")\n"
        info += "Haptic Feedback: \(isHapticEnabled ? "✅ Enabled" : "❌ Disabled")\n"
        info += "\nIf haptics don't work, check:\n"
        info += "Settings → Accessibility → Touch → Vibration"
        return info
    }

    // Diagnostic: check if haptics are actually available
    private func checkHapticAvailability() {
        LogManager.shared.log("Checking haptic availability...", category: "Haptic")
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        LogManager.shared.log("Haptic generator created and prepared", category: "Haptic", level: .success)
        LogManager.shared.log("Device: \(deviceModelName)", category: "Haptic")
        LogManager.shared.log("Has Taptic Engine: \(hasTapticEngine)", category: "Haptic")
        // Note: iOS doesn't provide a direct API to check if haptics are disabled in Settings
        // If you can't feel haptics, check:
        // 1. Settings > Accessibility > Touch > Haptics (must be ON)
        // 2. Low Power Mode should be OFF
        // 3. Silent switch should be OFF
        // 4. Test haptics from other apps (keyboard, Messages, etc.)
    }
    #endif

    // MARK: - Cross-platform diagnostic stubs

    #if !os(iOS)
    /// Non-iOS stub: always returns true (macOS always has haptic trackpad)
    var hasTapticEngine: Bool { return true }

    /// Non-iOS stub
    var deviceModelName: String { return "Mac" }

    /// Non-iOS stub: always returns false (no battery concern)
    var isLowPowerModeEnabled: Bool { return false }

    /// Non-iOS stub
    var diagnosticInfo: String {
        return "Device: \(deviceModelName)\nTaptic Engine: ✅ Available\nLow Power Mode: ✅ OFF\nHaptic Feedback: \(isHapticEnabled ? "✅ Enabled" : "❌ Disabled")"
    }
    #endif

    private init() {
        // Load the setting from UserDefaults, default to true
        self.isHapticEnabled = UserDefaults.standard.object(forKey: "hapticFeedbackEnabled") as? Bool ?? true

        #if os(iOS)
        // Pre-create the generator with heavy style for maximum noticeability
        scrollGenerator = UIImpactFeedbackGenerator(style: .heavy)
        scrollGenerator?.prepare()
        #endif
    }
    
    /// Triggers a haptic feedback for button presses
    func triggerButtonPress() {
        guard isHapticEnabled else {
            print("🔕 Haptic disabled")
            return
        }

        #if os(iOS)
        LogManager.shared.log("triggerButtonPress() called - using UISelectionFeedbackGenerator", category: "Haptic")
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.prepare()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            selectionFeedback.selectionChanged()
            LogManager.shared.log("Selection feedback triggered", category: "Haptic", level: .success)
        }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
    
    /// Triggers a subtle haptic tick for scroll wheel feedback
    func triggerScrollTick() {
        guard isHapticEnabled else { return }

        #if os(iOS)
        // Throttle to prevent iOS from suppressing rapid haptics (min 100ms between haptics)
        let now = Date()
        let timeSinceLastHaptic = now.timeIntervalSince(lastHapticTime)
        guard timeSinceLastHaptic >= 0.1 else {
            LogManager.shared.log("Haptic throttled (only \(String(format: "%.1f", timeSinceLastHaptic * 1000))ms since last)", category: "Haptic", level: .warning)
            return
        }
        lastHapticTime = now

        // Create a fresh generator for maximum reliability
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        LogManager.shared.log("Preparing haptic...", category: "Haptic")

        // Small delay to ensure preparation completes, then trigger
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            generator.impactOccurred()
            LogManager.shared.log("Haptic triggered (.light)", category: "Haptic", level: .success)
        }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }

    /// Triggers a medium haptic feedback for special actions
    func triggerMediumFeedback() {
        guard isHapticEnabled else { return }

        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            impactFeedback.impactOccurred()
        }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    /// Triggers a strong haptic feedback for important actions
    func triggerStrongFeedback() {
        guard isHapticEnabled else { return }

        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            impactFeedback.impactOccurred()
        }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }
    
    /// Toggles haptic feedback on/off
    func toggleHapticFeedback() {
        isHapticEnabled.toggle()
    }

    /// Test method to verify haptics are working - triggers the strongest possible haptic
    func testHaptic() {
        #if os(iOS)
        LogManager.shared.log("Testing haptic feedback...", category: "Haptic")
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            generator.impactOccurred()
            LogManager.shared.log("Test haptic triggered", category: "Haptic", level: .success)
        }
        #endif
    }
}
