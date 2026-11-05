//
//  KeyboardLayoutSettingsView.swift
//  KeyMod
//
//  Settings view for keyboard layout selection.
//

import SwiftUI

struct KeyboardLayoutSettingsView: View {
    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var layoutManager = KeyboardLayoutManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        Form {
            // MARK: - Auto Detection Section
            Section(header: Text(languageManager.localizedString("Auto Detection"))) {
                Toggle(languageManager.localizedString("Auto Detect Keyboard Layout"), isOn: $layoutManager.autoDetectLocale)

                if layoutManager.autoDetectLocale {
                    HStack {
                        Text(languageManager.localizedString("Detected Layout"))
                        Spacer()
                        Text(layoutManager.currentKeyboardLocale.displayName)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - Manual Selection Section
            Section(header: Text(languageManager.localizedString("Manual Selection"))) {
                if !layoutManager.autoDetectLocale {
                    Picker(languageManager.localizedString("Keyboard Layout"), selection: $layoutManager.currentKeyboardLocale) {
                        ForEach(KeyboardLocale.allCases) { locale in
                            HStack {
                                Text(locale.displayName)
                                Text("(\(locale.rawValue))")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .tag(locale)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }

            // MARK: - Current Layout Info Section
            Section(header: Text(languageManager.localizedString("Current Layout"))) {
                HStack {
                    Text(languageManager.localizedString("Layout Name"))
                    Spacer()
                    Text(layoutManager.activeLayoutName)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(languageManager.localizedString("Target System"))
                    Spacer()
                    Text(aiSettings.targetOS.displayName)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(languageManager.localizedString("Physical Standard"))
                    Spacer()
                    Text(layoutManager.activeLayout.metadata.physicalStandard.rawValue)
                        .foregroundColor(.secondary)
                }

                if layoutManager.availablePhysicalStandards.count > 1 {
                    Picker(
                        languageManager.localizedString("Physical Keyboard"),
                        selection: $layoutManager.physicalStandard
                    ) {
                        ForEach(layoutManager.availablePhysicalStandards, id: \.self) { standard in
                            Text(physicalStandardName(standard)).tag(standard)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(languageManager.localizedString("Choose the physical keyboard in front of you. A Japanese Mac can use either an ANSI (US) or a JIS keyboard."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if layoutManager.currentKeyboardLocale.physicalStandard == .iso {
                    HStack {
                        Text(languageManager.localizedString("AltGr Support"))
                        Spacer()
                        Text(layoutManager.activeLayout.metadata.hasAltGr ? languageManager.localizedString("Yes") : languageManager.localizedString("No"))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - Preview Section
            Section(header: Text(languageManager.localizedString("Layout Preview"))) {
                KeyboardLayoutPreviewView(layout: layoutManager.activeLayout)
                    .frame(height: 200)
            }

            // MARK: - Info Section
            Section(footer: Text(languageManager.localizedString("Keyboard layout determines the physical arrangement and labels of keys. Select the layout that matches your physical keyboard to ensure correct key mapping."))) {
                NavigationLink(languageManager.localizedString("View All Supported Layouts")) {
                    SupportedLayoutsListView()
                }
            }
        }
        .navigationTitle(languageManager.localizedString("Keyboard Layout"))
    }

    private func physicalStandardName(_ standard: KeyboardLocale.PhysicalStandard) -> String {
        switch standard {
        case .ansi: return languageManager.localizedString("ANSI (US)")
        case .iso:  return languageManager.localizedString("ISO")
        case .jis:  return languageManager.localizedString("JIS (Japanese)")
        }
    }
}

// MARK: - Keyboard Layout Preview

struct KeyboardLayoutPreviewView: View {
    let layout: KeyboardLayoutDefinition

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { keyIndex, key in
                            KeyPreviewView(key: key)
                                .frame(
                                    width: calculateKeyWidth(key: key, availableWidth: geometry.size.width),
                                    height: calculateRowHeight(rowIndex: rowIndex, availableHeight: geometry.size.height)
                                )
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
    }

    private func calculateKeyWidth(key: KeyDefinition, availableWidth: CGFloat) -> CGFloat {
        let baseWidth = (availableWidth - 8 * 2 - CGFloat(key.keyName.count) * 4) / CGFloat(layout.rows.first?.count ?? 14)
        return baseWidth * (key.widthMultiplier ?? 1.0)
    }

    private func calculateRowHeight(rowIndex: Int, availableHeight: CGFloat) -> CGFloat {
        let totalHeight = availableHeight - 8 * 2
        if let rowHeights = layout.metadata.rowHeights {
            return totalHeight * CGFloat(rowHeights[rowIndex])
        }
        return totalHeight / CGFloat(layout.rows.count)
    }
}

struct KeyPreviewView: View {
    let key: KeyDefinition

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(UIColor.systemGray5))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(UIColor.systemGray4), lineWidth: 1)
                )

            VStack(spacing: 2) {
                if let shiftLabel = key.shiftLabel {
                    Text(shiftLabel)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }

                Text(key.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)

                if let altGrLabel = key.altGrLabel {
                    Text(altGrLabel)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .padding(2)
        }
    }
}

// MARK: - Supported Layouts List

struct SupportedLayoutsListView: View {
    @ObservedObject private var languageManager = LanguageManager.shared
    var body: some View {
        List {
            ForEach(KeyboardLocale.allCases) { locale in
                Section(header: Text(locale.displayName)) {
                    HStack {
                        Text(languageManager.localizedString("Code"))
                        Spacer()
                        Text(locale.rawValue)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(languageManager.localizedString("Physical Standard"))
                        Spacer()
                        Text(locale.physicalStandard.rawValue)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(languageManager.localizedString("Supported Systems"))
                        Spacer()
                        Text(languageManager.localizedString("Windows, macOS, Linux"))
                            .foregroundColor(.secondary)
                    }

                    if let description = getLayoutDescription(for: locale) {
                        HStack {
                            Text(languageManager.localizedString("Features"))
                            Spacer()
                            Text(description)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .navigationTitle(languageManager.localizedString("Supported Layouts"))
    }

    private func getLayoutDescription(for locale: KeyboardLocale) -> String? {
        switch locale {
        case .us:
            return languageManager.localizedString("Standard US QWERTY layout")
        case .uk:
            return languageManager.localizedString("UK layout with £ on the 3 key")
        case .de:
            return languageManager.localizedString("German QWERTZ layout with Z and Y swapped")
        case .fr:
            return languageManager.localizedString("French AZERTY layout")
        case .es:
            return languageManager.localizedString("Spanish layout with Ñ key")
        case .it:
            return languageManager.localizedString("Italian layout with accent support")
        case .pt:
            return languageManager.localizedString("Portuguese layout with Ç key")
        case .jp:
            return languageManager.localizedString("Japanese JIS layout with special keys")
        case .cn:
            return languageManager.localizedString("Chinese US layout (same as US)")
        case .ca:
            return languageManager.localizedString("Canadian layout")
        case .au:
            return languageManager.localizedString("Australian layout (same as UK)")
        case .be:
            return languageManager.localizedString("Belgian AZERTY layout")
        case .ch:
            return languageManager.localizedString("Swiss QWERTZ layout")
        case .nordic:
            return languageManager.localizedString("Nordic layout with Å, Ä, Ö")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        KeyboardLayoutSettingsView()
    }
}
