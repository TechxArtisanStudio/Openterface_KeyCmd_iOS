//
//  AddModulePicker.swift
//  KeyMod
//
//  Picker sheet for adding a new gamepad module in edit mode.
//  Matches Android's 4 options: Touchpad, Scroll strip, D-Pad/Stick, Button.
//

import SwiftUI

struct AddModulePicker: View {
    @Binding var isPresented: Bool
    var onAdd: (AddModuleType) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Add Module") {
                    ForEach(AddModuleType.allCases, id: \.rawValue) { type in
                        Button {
                            onAdd(type)
                            isPresented = false
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.blue)
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.label)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(type.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add Module")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Add Module Types

enum AddModuleType: String, CaseIterable {
    case touchpad
    case scrollStrip
    case dpadStick
    case button

    var label: String {
        switch self {
        case .touchpad: return "Touchpad"
        case .scrollStrip: return "Scroll strip (mouse wheel)"
        case .dpadStick: return "D-Pad / Stick"
        case .button: return "Button"
        }
    }

    var subtitle: String {
        switch self {
        case .touchpad: return "Touch surface for mouse control"
        case .scrollStrip: return "Vertical scroll wheel area"
        case .dpadStick: return "Directional pad or analog stick"
        case .button: return "Single key action button"
        }
    }

    var icon: String {
        switch self {
        case .touchpad: return "trackpad"
        case .scrollStrip: return "arrow.up.arrow.down.circle"
        case .dpadStick: return "plus.circle"
        case .button: return "rectangle.fill"
        }
    }
}
