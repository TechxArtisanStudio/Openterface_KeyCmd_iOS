//
//  TouchpadSettings.swift
//  KeyMod
//
//  Created by System on 2025/7/15.
//

import Foundation
import SwiftUI

class TouchpadSettings: ObservableObject {
    static let shared = TouchpadSettings()

    @Published var tapDurationThreshold: Double {
        didSet {
            UserDefaults.standard.set(tapDurationThreshold, forKey: "tapDurationThreshold")
        }
    }

    @Published var tapMovementThreshold: Double {
        didSet {
            UserDefaults.standard.set(tapMovementThreshold, forKey: "tapMovementThreshold")
        }
    }

    @Published var tapDelayThreshold: Double {
        didSet {
            UserDefaults.standard.set(tapDelayThreshold, forKey: "tapDelayThreshold")
        }
    }

    /// Scroll sensitivity multiplier (0.2x - 2.0x, default 1.0x).
    /// Matches Android's touchpad_scroll_sensitivity preference.
    @Published var scrollSensitivity: Double {
        didSet {
            UserDefaults.standard.set(scrollSensitivity, forKey: "touchpad_scroll_sensitivity")
        }
    }

    private init() {
        self.tapDurationThreshold = UserDefaults.standard.object(forKey: "tapDurationThreshold") as? Double ?? 0.5
        self.tapMovementThreshold = UserDefaults.standard.object(forKey: "tapMovementThreshold") as? Double ?? 10.0
        self.tapDelayThreshold = UserDefaults.standard.object(forKey: "tapDelayThreshold") as? Double ?? 0.15
        self.scrollSensitivity = UserDefaults.standard.object(forKey: "touchpad_scroll_sensitivity") as? Double ?? 1.0
    }

    func resetToDefaults() {
        tapDurationThreshold = 0.5
        tapMovementThreshold = 10.0
        tapDelayThreshold = 0.15
        scrollSensitivity = 1.0
    }
}
