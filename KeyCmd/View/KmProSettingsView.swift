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
    @ObservedObject private var profileMgr = ShortcutProfileManager.shared
    @ObservedObject var keyboardManager: KeyboardManager

    var body: some View {
        // MARK: - Display section
        Section(header: Text("Keys display")) {
            Text("Same as the DISPLAY key at the end of row 1: how shortcuts on the strip look (names, icons, or combo text), and how Tab and the modifier keys on the main keyboard look.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
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
            Text("Letter keys show long-press hint glyphs for alternates. Turn off to hide hints and disable alternate popup.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Key Tap Preview", isOn: $prefs.keyTapPreviewEnabled)
            Text("Show a floating label above a held key while pressing.")
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

        // MARK: - Shortcut Hub profile section
        Section(header: Text("Shortcut Hub Profile")) {
            Text("Choose which profile's shortcuts appear on the keyboard strip.")
                .font(.caption)
                .foregroundColor(.secondary)

            profilePicker
        }
    }

    // MARK: - Profile Picker

    @State private var showProfilePickerSheet = false

    @ViewBuilder
    private var profilePicker: some View {
        if let active = profileMgr.activeProfile {
            Button(action: { showProfilePickerSheet = true }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(active.name)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("Tap to change")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("\(active.categories.count) categories, \(active.categories.reduce(0) { $0 + $1.shortcuts.count }) shortcuts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(PlainButtonStyle())
            .confirmationDialog("Select Profile", isPresented: $showProfilePickerSheet) {
                ForEach(profileMgr.profilesForPicking, id: \.id) { profile in
                    Button(profile.name) {
                        profileMgr.activeProfileId = profile.id
                    }
                }
            } message: {
                Text("Choose which profile's shortcuts appear on the keyboard strip.")
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
    private func modifierRow(value: KmBasicKeyboardPrefs.ModifierBehavior, title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
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
                KmProSettingsView(keyboardManager: KeyboardManager(bleManager: BLEManager()))
            }
        }
    }
}
