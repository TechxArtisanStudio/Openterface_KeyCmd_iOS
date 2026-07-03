//
//  KmBasicSettingsView.swift
//  KeyMod
//
//  Settings sections for Keyboard & Mouse (Basic) mode.
//  Ported from Android KeyboardMouseSettingsFragment.
//

import SwiftUI

struct KmBasicSettingsView: View {
    @ObservedObject private var prefs = KmBasicKeyboardPrefs.shared

    var body: some View {
        // MARK: - KM Basic Keyboard section
        Section(header: Text("KM Basic Keyboard")) {
            Text("Full keyboard in Keyboard + Mouse (Basic) mode: how Ctrl, Shift, Alt/Option, and Win/Cmd behave.")
                .font(.caption)
                .foregroundColor(.secondary)
            Toggle("Key Tap Preview", isOn: $prefs.keyTapPreviewEnabled)
            Text("Show a preview popup when you tap a key.")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        // MARK: - Modifier behaviour card
        Section(header: Text("Modifier Behavior")) {
            modifierRow(
                value: .sticky,
                title: "Sticky modifiers",
                description: "Tap once to latch a modifier on; tap again to turn off. Highlighted keys show what is latched."
            )
            modifierRow(
                value: .momentaryChord,
                title: "Momentary and long-press chord (default)",
                description: "Short tap sends that modifier key once to the target. Long-press a modifier, keep your finger down, then tap other keys to chord (e.g. long-press Shift and tap 1 for !). Release the modifier to stop."
            )
        }

        // MARK: - Chord sustain (only shown in momentary-chord mode)
        if prefs.modifierBehavior == .momentaryChord {
            Section(header: Text("Chord Sustain")) {
                Toggle("Hold modifier on target while chording", isOn: $prefs.chordSustainHid)
                Text("Sends a real modifier-down to the connected device when you long-press, and keeps it applied after each chorded key until you lift your finger. Turn off only if your host misbehaves with sustained modifiers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        // MARK: - Long-press behaviour card
        Section(header: Text("Long-Press Behavior")) {
            longPressRow(
                value: .repeat,
                title: "Repeat key presses while held (default)",
                description: "After a short delay, sends many quick press-and-release cycles — similar to auto-repeat when holding a physical key for typing."
            )
            longPressRow(
                value: .hold,
                title: "Hold key down on the target",
                description: "Sends one key-down when you press and releases when you lift your finger. Better for games or apps that expect a real held key instead of repeated taps."
            )
        }

        // MARK: - KM Basic Touchpad section
        Section(header: Text("KM Basic Touchpad")) {
            Text("Touchpad sub-mode in Keyboard & Mouse (Basic): the vertical strip at the right edge for page scroll.")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        Section(header: Text("Scroll Strip Sensitivity")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Vertical scroll strip sensitivity")
                    Spacer()
                    Text(String(format: "%.1fx", prefs.stripScrollSensitivity))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Slow")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(
                        value: $prefs.stripScrollSensitivity,
                        in: 0.2...2.0,
                        step: 0.1
                    )
                    Text("Fast")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("How fast content scrolls when you drag the strip beside the touchpad. Independent from General → touchpad two-finger scroll sensitivity.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func modifierRow(value: KmBasicKeyboardPrefs.ModifierBehavior, title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        Button(action: { withAnimation { prefs.modifierBehavior = value } }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: prefs.modifierBehavior == value ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(prefs.modifierBehavior == value ? .accentColor : .secondary)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.primary)
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

    @ViewBuilder
    private func longPressRow(value: KmBasicKeyboardPrefs.LongPressBehavior, title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        Button(action: { withAnimation { prefs.longPressBehavior = value } }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: prefs.longPressBehavior == value ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(prefs.longPressBehavior == value ? .accentColor : .secondary)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.primary)
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

struct KmBasicSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            KmBasicSettingsView()
        }
    }
}
