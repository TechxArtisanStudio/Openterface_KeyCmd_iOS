//
//  KeyPickerSheet.swift
//  KeyMod
//
//  Key picker dialog — matches Android's buildKeyPickerDialog.
//  Presents a scrollable grid of HID keys organized by section.
//

import SwiftUI

struct KeyPickerSheet: View {
    @Binding var isPresented: Bool
    @Binding var selectedKey: String    // derived key name (e.g. "W", "Enter")
    @Binding var selectedHidKey: Int    // HID keycode

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Letters
                    sectionHeader("Letters")
                    keyGrid(KeyPickerData.letters)

                    // Numbers
                    sectionHeader("Numbers")
                    keyGrid(KeyPickerData.numbers)

                    // Numpad
                    sectionHeader("Numpad")
                    keyGrid(KeyPickerData.numpad)

                    // Navigation
                    sectionHeader("Navigation")
                    keyGrid(KeyPickerData.navigation)

                    // Actions
                    sectionHeader("Actions")
                    keyGrid(KeyPickerData.actions)

                    // Modifiers
                    sectionHeader("Modifiers")
                    keyGrid(KeyPickerData.modifiers)
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Select Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func keyGrid(_ keys: [KeyPickerData.KeyOption]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(keys, id: \.hidCode) { opt in
                let isSelected = opt.hidCode == selectedHidKey
                Button {
                    selectedKey = opt.label
                    selectedHidKey = opt.hidCode
                    isPresented = false
                } label: {
                    Text(opt.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(isSelected ? Color.blue : Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

enum KeyPickerData {
    struct KeyOption {
        let label: String
        let hidCode: Int
    }

    static let letters: [KeyOption] = [
        .init(label: "W", hidCode: 26), .init(label: "A", hidCode: 4),
        .init(label: "S", hidCode: 22), .init(label: "D", hidCode: 7),
        .init(label: "J", hidCode: 13), .init(label: "K", hidCode: 14),
        .init(label: "L", hidCode: 15), .init(label: "I", hidCode: 12),
        .init(label: "U", hidCode: 24), .init(label: "O", hidCode: 18),
        .init(label: "P", hidCode: 19), .init(label: "H", hidCode: 11),
        .init(label: "G", hidCode: 10), .init(label: "F", hidCode: 9),
        .init(label: "Q", hidCode: 20), .init(label: "E", hidCode: 8),
        .init(label: "R", hidCode: 21), .init(label: "T", hidCode: 23),
        .init(label: "Y", hidCode: 28), .init(label: "Z", hidCode: 29),
        .init(label: "X", hidCode: 27), .init(label: "C", hidCode: 6),
        .init(label: "V", hidCode: 25), .init(label: "B", hidCode: 5),
        .init(label: "N", hidCode: 17), .init(label: "M", hidCode: 16),
    ]

    static let numbers: [KeyOption] = [
        .init(label: "1", hidCode: 30), .init(label: "2", hidCode: 31),
        .init(label: "3", hidCode: 32), .init(label: "4", hidCode: 33),
        .init(label: "5", hidCode: 34), .init(label: "6", hidCode: 35),
        .init(label: "7", hidCode: 36), .init(label: "8", hidCode: 37),
        .init(label: "9", hidCode: 38),
    ]

    static let numpad: [KeyOption] = [
        .init(label: "Num1", hidCode: 89), .init(label: "Num2", hidCode: 90),
        .init(label: "Num3", hidCode: 91), .init(label: "Num4", hidCode: 92),
        .init(label: "Num5", hidCode: 93), .init(label: "Num6", hidCode: 94),
        .init(label: "Num7", hidCode: 95), .init(label: "Num8", hidCode: 96),
        .init(label: "Num9", hidCode: 97),
    ]

    static let navigation: [KeyOption] = [
        .init(label: "↑", hidCode: 82), .init(label: "↓", hidCode: 83),
        .init(label: "←", hidCode: 81), .init(label: "→", hidCode: 80),
    ]

    static let actions: [KeyOption] = [
        .init(label: "Space", hidCode: 44), .init(label: "Enter", hidCode: 40),
        .init(label: "Esc", hidCode: 41), .init(label: "Tab", hidCode: 43),
        .init(label: "BS", hidCode: 42),
    ]

    static let modifiers: [KeyOption] = [
        .init(label: "Ctrl", hidCode: 224), .init(label: "Shift", hidCode: 225),
        .init(label: "Alt", hidCode: 226), .init(label: "Cmd", hidCode: 227),
    ]
}
