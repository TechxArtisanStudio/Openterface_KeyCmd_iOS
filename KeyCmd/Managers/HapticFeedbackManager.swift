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
    
    private init() {
        // Load the setting from UserDefaults, default to true
        self.isHapticEnabled = UserDefaults.standard.object(forKey: "hapticFeedbackEnabled") as? Bool ?? true
    }
    
    /// Triggers a light haptic feedback for button presses
    func triggerButtonPress() {
        guard isHapticEnabled else { return }
        
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
    
    /// Triggers a subtle haptic tick for scroll wheel feedback
    func triggerScrollTick() {
        guard isHapticEnabled else { return }

        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .rigid)
        impactFeedback.impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }

    /// Triggers a medium haptic feedback for special actions
    func triggerMediumFeedback() {
        guard isHapticEnabled else { return }
        
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }
    
    /// Triggers a strong haptic feedback for important actions
    func triggerStrongFeedback() {
        guard isHapticEnabled else { return }
        
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }
    
    /// Toggles haptic feedback on/off
    func toggleHapticFeedback() {
        isHapticEnabled.toggle()
    }
}
