//
//  KmBasicKeyboardPrefs.swift
//  KeyMod
//
//  Keyboard & Mouse (Basic) mode settings: modifier behavior, long-press behavior,
//  chord-sustain HID toggle, and scroll-strip sensitivity.
//  Matches Android KmBasicKeyboardPrefs / KmBasicTouchpadPrefs.
//

import Foundation

class KmBasicKeyboardPrefs: ObservableObject {
    static let shared = KmBasicKeyboardPrefs()

    // MARK: - Keys (matching Android)
    static let kModifierBehavior       = "km_basic_modifier_behavior"
    static let kChordSustainHid        = "km_basic_chord_sustain_hid"
    static let kLongPressBehavior      = "km_basic_long_press_behavior"
    static let kStripScrollSensitivity = "basic_touchpad_strip_scroll_sensitivity"

    // MARK: - Modifier behaviour

    /// How Ctrl / Shift / Alt / Win-Cmd respond in KM Basic keyboard mode.
    enum ModifierBehavior: String {
        /// Tap once to latch on; tap again to turn off. Highlighted keys show what is latched.
        case sticky = "sticky"
        /// Short tap sends that modifier key once. Long-press keeps it held so other keys can be
        /// chorded (e.g. long-press Shift → tap 1 → gets "!"). Release modifier to stop.
        case momentaryChord = "momentary_chord"
    }

    // MARK: - Long-press behaviour for regular keys

    /// What happens when a regular (non-modifier) key is held down in KM Basic keyboard mode.
    enum LongPressBehavior: String {
        /// After an initial delay, fires rapid press-and-release cycles (like physical auto-repeat).
        case `repeat` = "repeat"
        /// One key-down when pressed; one key-up when released. Better for games.
        case hold = "hold"
    }

    // MARK: - Published properties

    /// Default: momentaryChord (matching Android default VALUE_MOMENTARY_CHORD)
    @Published var modifierBehavior: ModifierBehavior {
        didSet {
            UserDefaults.standard.set(modifierBehavior.rawValue, forKey: Self.kModifierBehavior)
        }
    }

    /// Only relevant when modifierBehavior == .momentaryChord.
    /// Sends a real modifier-down HID report when long-pressing, and keeps it asserted until release.
    @Published var chordSustainHid: Bool {
        didSet {
            UserDefaults.standard.set(chordSustainHid, forKey: Self.kChordSustainHid)
        }
    }

    /// Default: repeat (matching Android default VALUE_LONG_PRESS_REPEAT)
    @Published var longPressBehavior: LongPressBehavior {
        didSet {
            UserDefaults.standard.set(longPressBehavior.rawValue, forKey: Self.kLongPressBehavior)
        }
    }

    /// Scroll strip sensitivity multiplier, 0.20 – 2.00 (default 1.0 = 100 %).
    /// Stored as integer percent (20–200) matching Android's int preference.
    @Published var stripScrollSensitivity: Double {
        didSet {
            let percent = Int((stripScrollSensitivity * 100).rounded())
            UserDefaults.standard.set(percent, forKey: Self.kStripScrollSensitivity)
        }
    }

    // MARK: - Convenience read-only accessors

    var isMomentaryChordMode: Bool { modifierBehavior == .momentaryChord }
    var isLongPressRepeatMode: Bool { longPressBehavior == .repeat }

    // MARK: - Init

    private init() {
        let ud = UserDefaults.standard

        let modRaw = ud.string(forKey: Self.kModifierBehavior) ?? ModifierBehavior.momentaryChord.rawValue
        self.modifierBehavior = ModifierBehavior(rawValue: modRaw) ?? .momentaryChord

        self.chordSustainHid = ud.object(forKey: Self.kChordSustainHid) as? Bool ?? true

        let lpRaw = ud.string(forKey: Self.kLongPressBehavior) ?? LongPressBehavior.repeat.rawValue
        self.longPressBehavior = LongPressBehavior(rawValue: lpRaw) ?? .repeat

        let sensitivityPct = ud.object(forKey: Self.kStripScrollSensitivity) as? Int ?? 100
        let clamped = max(20, min(200, sensitivityPct))
        self.stripScrollSensitivity = Double(clamped) / 100.0
    }
}
