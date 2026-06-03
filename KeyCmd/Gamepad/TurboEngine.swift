//
//  TurboEngine.swift
//  KeyMod
//
//  Timer-based key auto-repeat engine for gamepad turbo mode.
//  Sends key-down immediately, then repeats key-up/key-down at fixed interval.
//

import Foundation
import Combine

struct TurboConfig: Codable, Equatable {
    var enabled: Bool = false
    var intervalMs: Int = 80
    var initialDelayMs: Int = 400

    static let `default` = TurboConfig()
}

class TurboEngine: ObservableObject {
    @Published var isActive: Bool = false
    @Published var activeKey: String?

    private var repeatTimer: Timer?
    private var delayTimer: Timer?
    private weak var keyboardManager: KeyboardManager?
    private var keyToRepeat: String = ""
    private var config = TurboConfig.default

    init(keyboardManager: KeyboardManager) {
        self.keyboardManager = keyboardManager
    }

    /// Start turbo for the given key. Sends initial key-down immediately.
    func start(key: String, config: TurboConfig) {
        stop()
        self.keyToRepeat = key
        self.config = config
        isActive = true
        activeKey = key

        // Send initial key-down
        keyboardManager?.handleKeyDown(key)

        // Schedule auto-repeat after initial delay
        delayTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(config.initialDelayMs) / 1000.0,
            repeats: false
        ) { [weak self] _ in
            self?.beginRepeating()
        }
    }

    /// Stop turbo and release the key.
    func stop() {
        repeatTimer?.invalidate()
        delayTimer?.invalidate()
        repeatTimer = nil
        delayTimer = nil

        if isActive && !keyToRepeat.isEmpty {
            keyboardManager?.handleKeyUp(keyToRepeat)
        }

        isActive = false
        activeKey = nil
        keyToRepeat = ""
    }

    private func beginRepeating() {
        delayTimer = nil
        let interval = TimeInterval(config.intervalMs) / 1000.0
        guard interval > 0 else { return }

        repeatTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            guard let self = self, !self.keyToRepeat.isEmpty else { return }
            self.keyboardManager?.handleKeyUp(self.keyToRepeat)
            self.keyboardManager?.handleKeyDown(self.keyToRepeat)
        }
    }

    deinit {
        stop()
    }
}
