//
//  KeyboardLayoutManager.swift
//  KeyMod
//
//  Keyboard layout manager — singleton that provides the correct keyboard layout
//  for the current TargetOS + KeyboardLocale combination. All layouts are
//  lazily built and cached.
//

import Foundation
import SwiftUI

/// Keyboard layout manager - Singleton pattern
/// Responsible for providing the correct keyboard layout based on targetOS + keyboardLocale
final class KeyboardLayoutManager: ObservableObject {
    static let shared = KeyboardLayoutManager()

    // MARK: - Constants

    static let keyboardLocaleKey = "AISettings.keyboardLocale"
    static let keyboardAutoDetectKey = "AISettings.keyboardAutoDetect"
    static let physicalStandardKey = "AISettings.physicalKeyboardStandard"

    // MARK: - Published Properties

    /// The currently active layout
    @Published private(set) var currentLayout: KeyboardLayoutDefinition

    /// Currently selected keyboard locale
    @Published var currentKeyboardLocale: KeyboardLocale {
        didSet {
            guard currentKeyboardLocale != oldValue else { return }
            UserDefaults.standard.set(currentKeyboardLocale.rawValue, forKey: Self.keyboardLocaleKey)
            if !Self.supportedPhysicalStandards(for: currentKeyboardLocale).contains(physicalStandard) {
                physicalStandard = currentKeyboardLocale.physicalStandard
            }
            refreshCurrentLayout()
        }
    }

    /// Physical keyboard standard of the hardware in front of the user.
    ///
    /// A locale can have several physical variants (Japanese ships ANSI and JIS
    /// files). This describes the keyboard, not the target machine, so the
    /// target OS's input source stays untouched.
    @Published var physicalStandard: KeyboardLocale.PhysicalStandard {
        didSet {
            guard physicalStandard != oldValue else { return }
            UserDefaults.standard.set(physicalStandard.rawValue, forKey: Self.physicalStandardKey)
            refreshCurrentLayout()
        }
    }

    /// Whether auto-detection is enabled
    @Published var autoDetectLocale: Bool {
        didSet {
            UserDefaults.standard.set(autoDetectLocale, forKey: Self.keyboardAutoDetectKey)
            if autoDetectLocale {
                let detected = KeyboardLocale.fromSystemLocale()
                if detected != currentKeyboardLocale {
                    currentKeyboardLocale = detected
                }
            }
        }
    }

    // MARK: - Private Properties

    private var layoutCache: [String: KeyboardLayoutDefinition] = [:]
    private let logger = LogManager.shared
    private let prefs = KmBasicKeyboardPrefs.shared

    // MARK: - Init

    private init() {
        // Restore the last used layout. A saved locale is authoritative: it must
        // survive relaunches regardless of the auto-detect toggle.
        let resolvedLocale = Self.restoreLocale()
        let savedAutoDetect = UserDefaults.standard.object(forKey: Self.keyboardAutoDetectKey) as? Bool ?? false
        let resolvedStandard = Self.restorePhysicalStandard(for: resolvedLocale)

        let targetOS = AISettings.shared.targetOS

        // Initialize all stored properties first
        self.currentKeyboardLocale = resolvedLocale
        self.autoDetectLocale = savedAutoDetect
        self.physicalStandard = resolvedStandard
        self.currentLayout = Self.createLayout(
            for: targetOS,
            locale: resolvedLocale,
            physicalStandard: resolvedStandard
        )

        // Record the effective layout so the next launch restores exactly this one.
        UserDefaults.standard.set(resolvedLocale.rawValue, forKey: Self.keyboardLocaleKey)

        logger.log("KeyboardLayoutManager initialized: \(resolvedLocale.rawValue) layout for \(targetOS.rawValue)", category: "Keyboard")

        loadAllLayouts()
        observeSettingsChanges()
        setupKeyboardLayoutDetection()
    }

    /// Locale to restore at launch.
    ///
    /// A locale the user has selected before always wins. Auto-detection only
    /// provides the initial value on first launch, when nothing has been saved yet.
    static func restoreLocale(defaults: UserDefaults = .standard) -> KeyboardLocale {
        if let raw = defaults.string(forKey: keyboardLocaleKey),
           let saved = KeyboardLocale(rawValue: raw) {
            return saved
        }
        let autoDetect = defaults.object(forKey: keyboardAutoDetectKey) as? Bool ?? false
        return autoDetect ? KeyboardLocale.fromSystemLocale() : .us
    }

    /// Physical keyboard standard to restore at launch, defaulting to the
    /// locale's own standard (Japanese → JIS, US → ANSI, others → ISO).
    static func restorePhysicalStandard(
        for locale: KeyboardLocale,
        defaults: UserDefaults = .standard
    ) -> KeyboardLocale.PhysicalStandard {
        if let raw = defaults.string(forKey: physicalStandardKey),
           let saved = KeyboardLocale.PhysicalStandard(rawValue: raw),
           supportedPhysicalStandards(for: locale).contains(saved) {
            return saved
        }
        return locale.physicalStandard
    }

    /// Physical standards authored for a locale. Japanese has both the JIS
    /// keyboard and the ANSI keyboard used with a Japanese input source.
    static func supportedPhysicalStandards(
        for locale: KeyboardLocale
    ) -> [KeyboardLocale.PhysicalStandard] {
        locale == .jp ? [.jis, .ansi] : [locale.physicalStandard]
    }

    // MARK: - Public API

    /// Get all supported layouts
    var supportedLocales: [KeyboardLocale] { KeyboardLocale.allCases }

    /// Get layout for specified OS and Locale (with caching).
    /// Omitting `physicalStandard` yields the locale's default variant.
    func layout(
        for targetOS: TargetOS,
        locale: KeyboardLocale,
        physicalStandard: KeyboardLocale.PhysicalStandard? = nil
    ) -> KeyboardLayoutDefinition {
        let standard = physicalStandard ?? locale.physicalStandard
        let key = Self.cacheKey(targetOS, locale, standard)
        if let cached = layoutCache[key] {
            return cached
        }
        let layout = Self.createLayout(for: targetOS, locale: locale, physicalStandard: standard)
        layoutCache[key] = layout
        return layout
    }

    /// Currently active layout (based on current settings)
    var activeLayout: KeyboardLayoutDefinition {
        currentLayout
    }

    /// Resolve display key name to HID key name using current layout
    func hidKeyName(for keyName: String) -> String {
        if keyName == "Esc" { return "Escape" }
        return currentLayout.keyDefinition(for: keyName)?.keyCode ?? keyName
    }

    /// Preload all layout combinations
    func preloadAllLayouts() {
        DispatchQueue.global(qos: .utility).async {
            for os in TargetOS.allCases {
                for locale in KeyboardLocale.allCases {
                    _ = self.layout(for: os, locale: locale, physicalStandard: locale.physicalStandard)
                }
            }
            self.logger.log("All keyboard layouts preloaded", category: "Keyboard")
        }
    }

    /// Get current active layout name
    var activeLayoutName: String {
        currentLayout.metadata.name
    }

    /// Physical keyboard standards offered in the UI. Only variants that are
    /// actually authored for the current locale + target OS are listed.
    var availablePhysicalStandards: [KeyboardLocale.PhysicalStandard] {
        if currentKeyboardLocale == .jp, AISettings.shared.targetOS == .macOS {
            return [.jis, .ansi]
        }
        return [currentKeyboardLocale.physicalStandard]
    }

    /// Cache statistics
    var cacheStats: String {
        "\(layoutCache.count) layouts cached"
    }

    /// Clear the layout cache (useful for testing)
    func clearCache() {
        layoutCache.removeAll()
    }

    // MARK: - Layout Creation

    private static func cacheKey(
        _ os: TargetOS,
        _ locale: KeyboardLocale,
        _ physicalStandard: KeyboardLocale.PhysicalStandard
    ) -> String {
        "\(os.rawValue)_\(locale.rawValue)_\(physicalStandard.rawValue)"
    }

    /// Create layout for specified OS and Locale (delegated to corresponding builder)
    static func createLayout(
        for targetOS: TargetOS,
        locale: KeyboardLocale,
        physicalStandard: KeyboardLocale.PhysicalStandard? = nil
    ) -> KeyboardLayoutDefinition {
        let standard = physicalStandard ?? locale.physicalStandard
        switch targetOS {
        case .windows:
            return WindowsLayoutBuilder.build(for: locale, physicalStandard: standard)
        case .macOS:
            return MacLayoutBuilder.build(for: locale, physicalStandard: standard)
        case .linux:
            return LinuxLayoutBuilder.build(for: locale, physicalStandard: standard)
        }
    }

    // MARK: - Private Methods

    private func loadAllLayouts() {
        // Preload commonly used locales for current targetOS
        let priorityLocales: [KeyboardLocale] = [.us, .uk, .de, .fr, .jp, .cn]
        for locale in priorityLocales {
            _ = layout(
                for: AISettings.shared.targetOS,
                locale: locale,
                physicalStandard: locale.physicalStandard
            )
            // Warm the user's own variant too when it differs from the default.
            if locale == currentKeyboardLocale, physicalStandard != locale.physicalStandard {
                _ = layout(
                    for: AISettings.shared.targetOS,
                    locale: locale,
                    physicalStandard: physicalStandard
                )
            }
        }
    }

    private func observeSettingsChanges() {
        // Observe targetOS changes to update layout
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTargetOSChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    private func setupKeyboardLayoutDetection() {
        // Do not run detection here: the saved locale was already restored by init,
        // and re-detecting at launch would silently overwrite the user's choice.
        // Live input-mode changes are handled by the notification observer below.
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardLayoutChanged),
            name: UITextInputMode.currentInputModeDidChangeNotification,
            object: nil
        )
        #endif
    }

    @objc private func handleTargetOSChanged() {
        let currentOS = AISettings.shared.targetOS
        let layoutOS = currentLayout.targetOS
        if currentOS != layoutOS {
            refreshCurrentLayout()
        }
    }

    #if os(iOS)
    @objc private func handleKeyboardLayoutChanged() {
        if autoDetectLocale, let detected = KeyboardLocale.detectActiveKeyboardLayout() {
            if detected != currentKeyboardLocale {
                currentKeyboardLocale = detected
                logger.log("Keyboard layout changed to: \(detected.rawValue)", category: "Keyboard")
                objectWillChange.send()
            }
        }
    }
    #endif

    private func refreshCurrentLayout() {
        let newLayout = layout(
            for: AISettings.shared.targetOS,
            locale: currentKeyboardLocale,
            physicalStandard: physicalStandard
        )
        currentLayout = newLayout
        logger.log(
            "Keyboard layout refreshed: \(currentKeyboardLocale.rawValue) \(physicalStandard.rawValue) for \(AISettings.shared.targetOS.rawValue)",
            category: "Keyboard"
        )
        objectWillChange.send()
        notifyLayoutChanged()
    }

    private func notifyLayoutChanged() {
        NotificationCenter.default.post(
            name: .keyboardLayoutChanged,
            object: self,
            userInfo: ["layout": currentLayout]
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Sent when keyboard layout changes
    static let keyboardLayoutChanged = Notification.Name("KeyboardLayoutChanged")
    /// Sent when keyboard locale setting changes
    static let keyboardLocaleChanged = Notification.Name("KeyboardLocaleChanged")
}

// MARK: - AISettings Extension

extension AISettings {
    /// Convenient access to keyboard locale setting
    var keyboardLocale: KeyboardLocale {
        get {
            KeyboardLayoutManager.shared.currentKeyboardLocale
        }
        set {
            KeyboardLayoutManager.shared.currentKeyboardLocale = newValue
        }
    }

    /// Convenient access to keyboard auto-detection setting
    var keyboardAutoDetect: Bool {
        get {
            KeyboardLayoutManager.shared.autoDetectLocale
        }
        set {
            KeyboardLayoutManager.shared.autoDetectLocale = newValue
        }
    }

    /// Convenient access to the physical keyboard standard (ANSI / ISO / JIS)
    var keyboardPhysicalStandard: KeyboardLocale.PhysicalStandard {
        get {
            KeyboardLayoutManager.shared.physicalStandard
        }
        set {
            KeyboardLayoutManager.shared.physicalStandard = newValue
        }
    }
}