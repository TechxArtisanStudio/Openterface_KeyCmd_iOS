//
//  KeyRepeatController.swift
//  KeyMod
//
//  Manages key repeat on long-press for arrow keys and backspace.
//  Matches Android CustomKeyboardView.startRepeatingDelete() behavior:
//  - Initial long-press timeout: ~400ms
//  - Repeat interval: 10ms
//

import Foundation
import UIKit

class KeyRepeatController: ObservableObject {
    private var repeatTimer: Timer?
    private var initialPressTimer: Timer?
    private let initialDelay: TimeInterval = 0.4  // 400ms before repeat starts
    private let repeatInterval: TimeInterval = 0.01  // 10ms between repeats
    private var keyAction: (() -> Void)?
    private var isRepeating = false

    static let shared = KeyRepeatController()

    /// Keys that should auto-repeat on long-press (matches Android)
    static let repeatableKeys = ["Up", "Down", "Left", "Right", "Backspace",
                                  "Delete", "Arrow_up", "Arrow_down", "Arrow_left", "Arrow_right",
                                  "↑", "↓", "←", "→"]

    /// Start monitoring for long-press repeat. If the press is held beyond initialDelay,
    /// keyAction will be called repeatedly at repeatInterval until stopRepeating().
    func startRepeating(keyAction: @escaping () -> Void) {
        stopRepeating()
        self.keyAction = keyAction
        isRepeating = false

        initialPressTimer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isRepeating = true
            self.keyAction?()  // First repeat
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: self.repeatInterval, repeats: true) { [weak self] _ in
                self?.keyAction?()
            }
        }
    }

    /// Stop all repeat timers.
    func stopRepeating() {
        initialPressTimer?.invalidate()
        initialPressTimer = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
        isRepeating = false
    }

    var isCurrentlyRepeating: Bool {
        return isRepeating
    }
}
