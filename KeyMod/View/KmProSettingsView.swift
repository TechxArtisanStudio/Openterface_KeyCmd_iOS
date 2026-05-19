//
//  KmProSettingsView.swift
//  KeyMod
//
//  Settings for Keyboard & Mouse (Pro) mode.
//  Ported from Android KmProSettingsFragment.
//

import SwiftUI

struct KmProSettingsView: View {
    @ObservedObject private var prefs = KmProPrefs.shared
    @ObservedObject private var basicPrefs = KmBasicKeyboardPrefs.shared

    var body: some View {
        // MARK: - Display section
        Section(header: Text("Display")) {
            Text("Controls how shortcuts and keys appear on the keyboard strip and QWERTY layout.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Keys Display")
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 12) {
                    ForEach(KmProPrefs.KeysDisplayMode.allCases, id: \.self) { mode in
                        keysDisplayButton(mode: mode)
                    }
                }
            }
            .padding(.vertical, 4)
        }

        // MARK: - Typing section
        Section(header: Text("Typing")) {
            Toggle("Alternate Hints", isOn: $prefs.alternateHintsEnabled)
            Text("Letter keys show long-press hint glyphs for alternates. Turn off for hold-to-repeat gaming style.")
                .font(.caption)
                .foregroundColor(.secondary)

            if !prefs.alternateHintsEnabled {
                gamingKeyBehaviorSection
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Toggle("Key Tap Preview", isOn: $prefs.keyTapPreviewEnabled)
            Text("Show a floating label above a held key while pressing.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Compose Draft Retention", isOn: $prefs.composeDraftRetentionEnabled)
            Text("Remember compose text while switching to Keyboard or NumPad submodes (in-memory only).")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        // MARK: - Touchpad section
        Section(header: Text("Touchpad")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Touchpad Mode")
                    .font(.subheadline)
                    .fontWeight(.medium)
                ForEach(KmProPrefs.TouchpadMode.allCases, id: \.self) { mode in
                    touchpadModeButton(mode: mode)
                }
            }
            .padding(.vertical, 4)

            Toggle("Vertical Scroll Strip", isOn: $prefs.scrollStripEnabled)
            Text("Show drag strip beside touchpad for mouse wheel scroll.")
                .font(.caption)
                .foregroundColor(.secondary)

            if prefs.scrollStripEnabled {
                scrollSensitivitySection
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Toggle("Gesture Status Line", isOn: $prefs.gestureStatusVisible)
            Text("Show compact gesture status line on touchpad (buttons up / touch idle).")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        // MARK: - Modifiers section (shared with Basic)
        Section(header: Text("Modifiers (shared with Basic)")) {
            Text("These settings also apply in Keyboard & Mouse (Basic) mode.")
                .font(.caption)
                .foregroundColor(.secondary)

            modifierRow(
                value: .sticky,
                title: "Sticky modifiers",
                description: "Tap once to latch a modifier on; tap again to turn off."
            )
            modifierRow(
                value: .momentaryChord,
                title: "Momentary and long-press chord",
                description: "Short tap sends modifier once. Long-press to chord with other keys."
            )
        }

        if basicPrefs.modifierBehavior == .momentaryChord {
            Section(header: Text("Chord Sustain")) {
                Toggle("Hold modifier on target while chording", isOn: $basicPrefs.chordSustainHid)
                Text("Sends a real modifier-down to the connected device when long-pressing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func keysDisplayButton(mode: KmProPrefs.KeysDisplayMode) -> some View {
        Button(action: { withAnimation { prefs.keysDisplayMode = mode } }) {
            VStack(spacing: 4) {
                Image(systemName: prefs.keysDisplayMode == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(prefs.keysDisplayMode == mode ? .accentColor : .secondary)
                    .font(.system(size: 18))
                Text(mode.label)
                    .font(.caption)
                    .foregroundColor(prefs.keysDisplayMode == mode ? .primary : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func touchpadModeButton(mode: KmProPrefs.TouchpadMode) -> some View {
        Button(action: { withAnimation { prefs.touchpadMode = mode } }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: prefs.touchpadMode == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(prefs.touchpadMode == mode ? .accentColor : .secondary)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .foregroundColor(.primary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var gamingKeyBehaviorSection: some View {
        Group {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Gaming Key Behavior")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                longPressRow(value: .repeat, title: "Repeat key presses", description: "Rapid tap cycles while held.")
                longPressRow(value: .hold, title: "Hold key down", description: "One key-down until release. Better for games.")
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func longPressRow(value: KmBasicKeyboardPrefs.LongPressBehavior, title: String, description: String) -> some View {
        Button(action: { withAnimation { basicPrefs.longPressBehavior = value } }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: basicPrefs.longPressBehavior == value ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(basicPrefs.longPressBehavior == value ? .accentColor : .secondary)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var scrollSensitivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Strip Scroll Sensitivity")
                Spacer()
                Text(String(format: "%.1fx", prefs.stripScrollSensitivity))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Text("Slow").font(.caption).foregroundColor(.secondary)
                Slider(value: $prefs.stripScrollSensitivity, in: 0.2...2.0, step: 0.1)
                Text("Fast").font(.caption).foregroundColor(.secondary)
            }
            Text("How fast content scrolls when dragging the strip.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func modifierRow(value: KmBasicKeyboardPrefs.ModifierBehavior, title: String, description: String) -> some View {
        Button(action: { withAnimation { basicPrefs.modifierBehavior = value } }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: basicPrefs.modifierBehavior == value ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(basicPrefs.modifierBehavior == value ? .accentColor : .secondary)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct KmProSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            Form {
                KmProSettingsView()
            }
        }
    }
}
