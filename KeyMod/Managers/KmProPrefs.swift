//
//  KmProPrefs.swift
//  KeyMod
//
//  Keyboard & Mouse Pro mode settings: keys display, alternate hints, key tap
//  preview, compose draft retention, touchpad mode, scroll strip, gesture status.
//  Matches Android KmProSettingsFragment / related prefs classes.
//

import Foundation

class KmProPrefs: ObservableObject {
    static let shared = KmProPrefs()

    // MARK: - Keys (matching Android)
    static let kKeysDisplay           = "top_shortcut_display_mode"       // Int: 0=Names, 1=Icons, 2=Combo
    static let kAlternateHints        = "keyboard_alternates_hints_enabled"
    static let kKeyTapPreview        = "km_pro_key_tap_preview_enabled"
    static let kComposeDraftRetention = "km_pro_compose_draft_retention_enabled"
    static let kTouchpadMode         = "km_pro_touchpad_mode"            // Int: 0=Gestures, 1=Pad+Mouse, 2=Hybrid
    static let kScrollStripEnabled   = "km_pro_touchpad_scroll_strip_enabled"
    static let kStripSensitivity     = "km_pro_touchpad_strip_scroll_sensitivity"
    static let kGestureStatusVisible = "km_pro_touchpad_gesture_status_visible"

    // MARK: - Keys Display

    enum KeysDisplayMode: Int, CaseIterable {
        case names = 0, icons, combo
        var label: String {
            switch self {
            case .names: return "Names"
            case .icons: return "Icons"
            case .combo: return "Combo"
            }
        }
    }

    @Published var keysDisplayMode: KeysDisplayMode {
        didSet {
            UserDefaults.standard.set(keysDisplayMode.rawValue, forKey: Self.kKeysDisplay)
        }
    }

    // MARK: - Alternate Hints

    @Published var alternateHintsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(alternateHintsEnabled, forKey: Self.kAlternateHints)
        }
    }

    // MARK: - Key Tap Preview

    @Published var keyTapPreviewEnabled: Bool {
        didSet {
            UserDefaults.standard.set(keyTapPreviewEnabled, forKey: Self.kKeyTapPreview)
        }
    }

    // MARK: - Compose Draft Retention

    @Published var composeDraftRetentionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(composeDraftRetentionEnabled, forKey: Self.kComposeDraftRetention)
        }
    }

    // MARK: - Touchpad Mode

    enum TouchpadMode: Int, CaseIterable {
        case gesturesOnly = 0, padAndMouseKeys, hybrid
        var label: String {
            switch self {
            case .gesturesOnly: return "Gestures only"
            case .padAndMouseKeys: return "Pad + mouse keys"
            case .hybrid: return "Hybrid"
            }
        }
        var description: String {
            switch self {
            case .gesturesOnly: return "Touchpad gestures control the pointer only."
            case .padAndMouseKeys: return "Left/middle/right strip for mouse clicks."
            case .hybrid: return "Full touchpad gestures plus L/M/R strip with visual sync."
            }
        }
    }

    @Published var touchpadMode: TouchpadMode {
        didSet {
            UserDefaults.standard.set(touchpadMode.rawValue, forKey: Self.kTouchpadMode)
        }
    }

    // MARK: - Scroll Strip

    @Published var scrollStripEnabled: Bool {
        didSet {
            UserDefaults.standard.set(scrollStripEnabled, forKey: Self.kScrollStripEnabled)
        }
    }

    @Published var stripScrollSensitivity: Double {
        didSet {
            let percent = Int((stripScrollSensitivity * 100).rounded())
            UserDefaults.standard.set(percent, forKey: Self.kStripSensitivity)
        }
    }

    // MARK: - Gesture Status Line

    @Published var gestureStatusVisible: Bool {
        didSet {
            UserDefaults.standard.set(gestureStatusVisible, forKey: Self.kGestureStatusVisible)
        }
    }

    // MARK: - Init

    private init() {
        let ud = UserDefaults.standard

        let kdRaw = ud.integer(forKey: Self.kKeysDisplay)
        self.keysDisplayMode = KeysDisplayMode(rawValue: kdRaw) ?? .icons

        self.alternateHintsEnabled = ud.object(forKey: Self.kAlternateHints) as? Bool ?? true
        self.keyTapPreviewEnabled = ud.object(forKey: Self.kKeyTapPreview) as? Bool ?? true
        self.composeDraftRetentionEnabled = ud.object(forKey: Self.kComposeDraftRetention) as? Bool ?? true

        let tpRaw = ud.integer(forKey: Self.kTouchpadMode)
        self.touchpadMode = TouchpadMode(rawValue: tpRaw) ?? .gesturesOnly

        self.scrollStripEnabled = ud.object(forKey: Self.kScrollStripEnabled) as? Bool ?? true

        let sensitivityPct = ud.object(forKey: Self.kStripSensitivity) as? Int ?? 100
        let clamped = max(20, min(200, sensitivityPct))
        self.stripScrollSensitivity = Double(clamped) / 100.0

        self.gestureStatusVisible = ud.object(forKey: Self.kGestureStatusVisible) as? Bool ?? true
    }
}
