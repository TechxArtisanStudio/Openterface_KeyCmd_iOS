//
//  BackgroundPickerView.swift
//  KeyMod
//
//  UI for gamepad background customization: type selection, color, pattern,
//  image import, and pan/zoom controls.
//

import SwiftUI
import PhotosUI

@available(iOS 16.0, *)
struct BackgroundPickerView: View {
    @ObservedObject var manager: GamepadBackgroundManager
    @Binding var isPresented: Bool
    var onSave: (() -> Void)?
    @State private var showImagePicker = false
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        NavigationView {
            Form {
                Section("Background Type") {
                    Picker("Type", selection: $manager.backgroundType) {
                        ForEach(BackgroundType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                // Solid Color
                if manager.backgroundType == .solidColor {
                    Section("Color") {
                        ColorPicker("Background Color", selection: Binding(
                            get: { Color(hex: manager.solidColorHex) },
                            set: {
                                manager.solidColorHex = colorToHex($0)
                                manager.saveConfig()
                            }
                        ))
                        Text(manager.solidColorHex)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Gradient
                if manager.backgroundType == .gradient {
                    Section("Gradient") {
                        ColorPicker("Top Color", selection: Binding(
                            get: { Color(hex: manager.gradientTopHex) },
                            set: {
                                manager.gradientTopHex = colorToHex($0)
                                manager.saveConfig()
                            }
                        ))
                        ColorPicker("Bottom Color", selection: Binding(
                            get: { Color(hex: manager.gradientBottomHex) },
                            set: {
                                manager.gradientBottomHex = colorToHex($0)
                                manager.saveConfig()
                            }
                        ))
                    }
                }

                // Pattern
                if manager.backgroundType == .pattern {
                    Section("Pattern") {
                        Picker("Pattern", selection: $manager.pattern) {
                            ForEach(BackgroundPattern.allCases.filter { $0 != .none }, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())

                        ColorPicker("Background Color", selection: Binding(
                            get: { Color(hex: manager.gradientTopHex) },
                            set: { manager.gradientTopHex = colorToHex($0) }
                        ))
                    }
                }

                // Custom Image
                if manager.backgroundType == .image {
                    Section("Image") {
                        if manager.backgroundImage != nil {
                            VStack {
                                Text("Current Background")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                PhotosPicker(
                                    selection: $selectedItem,
                                    matching: .images,
                                    photoLibrary: .shared()
                                ) {
                                    Text("Change Image")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button("Remove Image", role: .destructive) {
                                    manager.removeImage()
                                }
                            }
                        } else {
                            PhotosPicker(
                                selection: $selectedItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Label("Choose Image", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Pan/Zoom (only for image mode)
                    if manager.backgroundImage != nil {
                        Section("Pan & Zoom") {
                            VStack {
                                HStack {
                                    Text("Zoom")
                                    Slider(value: $manager.bgScale, in: 0.5...3.0) {
                                        Text("Zoom")
                                    }
                                    Text(String(format: "%.1fx", manager.bgScale))
                                        .font(.caption)
                                        .frame(width: 40)
                                }
                                HStack {
                                    Text("X Offset")
                                    Slider(value: $manager.bgOffsetX, in: -300...300) {
                                        Text("X Offset")
                                    }
                                    Text(String(format: "%.0f", manager.bgOffsetX))
                                        .font(.caption)
                                        .frame(width: 40)
                                }
                                HStack {
                                    Text("Y Offset")
                                    Slider(value: $manager.bgOffsetY, in: -300...300) {
                                        Text("Y Offset")
                                    }
                                    Text(String(format: "%.0f", manager.bgOffsetY))
                                        .font(.caption)
                                        .frame(width: 40)
                                }
                                Button("Reset Transform") {
                                    manager.resetTransform()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave?()
                        isPresented = false
                    }
                }
            }
            .onChange(of: selectedItem) { item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        manager.setImage(image)
                    }
                }
            }
        }
    }

    private func colorToHex(_ color: Color) -> String {
        // SwiftUI Color doesn't have a built-in hex converter;
        // Use UIColor's CGColor for conversion
        let cgColor = UIColor(color).cgColor
        guard let components = cgColor.components,
              components.count >= 3 else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
