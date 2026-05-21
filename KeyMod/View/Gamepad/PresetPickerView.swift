//
//  PresetPickerView.swift
//  KeyMod
//
//  Preset selection, import, export, and management UI.
//  Shows a grid of preset cards with preview thumbnails, matching Android's layout picker.
//

import SwiftUI

struct PresetPickerView: View {
    @ObservedObject var repository: GamepadPresetRepository
    @Binding var isPresented: Bool
    @State private var showImportPicker = false
    @State private var showRenameSheet = false
    @State private var renameTargetId: String = ""
    @State private var renameText: String = ""
    @State private var isReorderMode = false
    @State private var selectedPresetForMenu: PresetRef?
    @State private var presetDocuments: [String: GamepadPresetDocument] = [:]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Preset grid
                ScrollView {
                    LazyVGrid(columns: presetGridColumns, spacing: 12) {
                        ForEach(repository.presets) { preset in
                            let doc = presetDocuments[preset.id]
                            PresetCard(
                                preset: preset,
                                document: doc,
                                isActive: preset.id == repository.activePresetId,
                                isReorderMode: isReorderMode,
                                onTap: {
                                    repository.activatePreset(id: preset.id)
                                    isPresented = false
                                },
                                onMore: {
                                    selectedPresetForMenu = preset
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // New layout button
                            Button {
                                if let newId = repository.createEmptyPreset() {
                                    loadDocument(for: newId)
                                    repository.activatePreset(id: newId)
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                            }

                            // Import button
                            Button {
                                showImportPicker = true
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                            }

                            // Reorder toggle
                            Button {
                                withAnimation {
                                    isReorderMode.toggle()
                                }
                            } label: {
                                Image(systemName: isReorderMode ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(isReorderMode ? .orange : .secondary)
                            }
                        }
                    }
                    .frame(maxWidth: 140)
                }
            }
            .onAppear {
                // Load all preset documents for previews
                for preset in repository.presets {
                    loadDocument(for: preset.id)
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.json]
            ) { result in
                if let url = try? result.get() {
                    if let newId = try? repository.importPreset(from: url) {
                        loadDocument(for: newId)
                    }
                }
            }
            .alert("Rename Preset", isPresented: $showRenameSheet) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if !renameText.isEmpty {
                        repository.renamePreset(id: renameTargetId, newName: renameText)
                        loadDocument(for: renameTargetId)
                    }
                }
            } message: {
                Text("Enter a new name for this preset.")
            }
            .actionSheet(item: $selectedPresetForMenu) { preset in
                ActionSheet(
                    title: Text(preset.displayName),
                    buttons: presetActionSheetButtons(for: preset)
                )
            }
        }
    }

    private var presetGridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private func loadDocument(for id: String) {
        if let doc = repository.loadDocument(id: id) {
            presetDocuments[id] = doc
        }
    }

    private func presetActionSheetButtons(for preset: PresetRef) -> [ActionSheet.Button] {
        var buttons: [ActionSheet.Button] = []

        if !preset.isBuiltin {
            buttons.append(.default(Text("Duplicate")) {
                if let newId = repository.duplicatePreset(id: preset.id) {
                    loadDocument(for: newId)
                }
            })
            buttons.append(.default(Text("Rename")) {
                renameTargetId = preset.id
                renameText = preset.displayName
                showRenameSheet = true
            })
            buttons.append(.default(Text("Export")) {
                _ = repository.exportPreset(id: preset.id)
            })
            buttons.append(.destructive(Text("Delete")) {
                repository.deletePreset(id: preset.id)
                presetDocuments.removeValue(forKey: preset.id)
            })
        } else {
            buttons.append(.default(Text("Export")) {
                _ = repository.exportPreset(id: preset.id)
            })
        }
        buttons.append(.cancel())
        return buttons
    }
}

// MARK: - Preset Card

struct PresetCard: View {
    let preset: PresetRef
    let document: GamepadPresetDocument?
    let isActive: Bool
    let isReorderMode: Bool
    let onTap: () -> Void
    let onMore: () -> Void

    @StateObject private var hapticManager = HapticFeedbackManager.shared

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Preview area
                ZStack(alignment: .topTrailing) {
                    // Preview canvas
                    Group {
                        if let doc = document {
                            PresetPreviewCard(modules: doc.modules)
                                .frame(height: 96)
                                .cornerRadius(10, corners: [.topLeft, .topRight])
                        } else {
                            Color(UIColor.secondarySystemBackground)
                                .overlay(
                                    Image(systemName: "gamecontroller")
                                        .font(.system(size: 28))
                                        .foregroundColor(.secondary.opacity(0.5))
                                )
                                .frame(height: 96)
                                .cornerRadius(10, corners: [.topLeft, .topRight])
                        }
                    }

                    // Built-in indicator
                    if preset.isBuiltin {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.blue.opacity(0.8))
                            .clipShape(Circle())
                            .padding(6)
                    }

                    // Reorder handle
                    if isReorderMode {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.gray.opacity(0.7))
                            .clipShape(Circle())
                            .padding(6)
                    }
                }

                // Title bar
                HStack(spacing: 0) {
                    Text(preset.displayName)
                        .font(.system(size: 13, weight: isActive ? .bold : .regular))
                        .foregroundColor(isActive ? .blue : .primary)
                        .lineLimit(1)
                    Spacer()

                    // More button
                    Button(action: onMore) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(10, corners: [.bottomLeft, .bottomRight])
            }
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
        )
        .shadow(color: isActive ? Color.blue.opacity(0.3) : Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preset Preview Card

struct PresetPreviewCard: View {
    let modules: [GamepadModule]

    var body: some View {
        ZStack {
            // Grid pattern background
            PresetPreviewGridPattern()

            // Module indicators
            ForEach(modules.prefix(20), id: \.id) { module in
                ModuleIndicator(module: module)
                    .position(
                        x: CGFloat(module.anchorX) * 100,
                        y: CGFloat(module.anchorY) * 48
                    )
            }

            // Module count badge
            if !modules.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(modules.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(4)
                            .padding(4)
                    }
                }
            }
        }
    }
}

struct ModuleIndicator: View {
    let module: GamepadModule

    var moduleSize: CGSize {
        let base: CGFloat = 10 * module.scale
        switch module.type {
        case .button: return CGSize(width: base, height: base)
        case .dpad: return CGSize(width: base * 2, height: base * 2)
        case .analogStick: return CGSize(width: base * 1.5, height: base * 1.5)
        case .scrollStrip: return CGSize(width: base * 0.5, height: base * 2.5)
        case .touchpad: return CGSize(width: base * 3, height: base * 2)
        case .mouseButton: return CGSize(width: base * 0.7, height: base * 0.7)
        case .shoulder: return CGSize(width: base * 1.5, height: base * 0.6)
        case .trigger: return CGSize(width: base * 1.2, height: base * 0.5)
        }
    }

    var moduleColor: Color {
        if let argb = module.moduleAccentArgb {
            return Color(argb: argb)
        }
        switch module.type {
        case .button: return .blue
        case .dpad: return .gray
        case .analogStick: return .purple
        case .scrollStrip: return .green
        case .touchpad: return .cyan
        case .mouseButton: return .orange
        case .shoulder: return .red
        case .trigger: return .pink
        }
    }

    var body: some View {
        Group {
            switch module.type {
            case .dpad:
                RoundedRectangle(cornerRadius: 2)
                    .fill(moduleColor.opacity(0.7))
                    .frame(width: moduleSize.width, height: moduleSize.height)
                    .overlay(
                        Rectangle()
                            .fill(moduleColor.opacity(0.7))
                            .frame(width: moduleSize.height, height: moduleSize.width)
                    )
            case .analogStick:
                Circle()
                    .fill(moduleColor.opacity(0.5))
                    .frame(width: moduleSize.width, height: moduleSize.height)
                    .overlay(
                        Circle()
                            .stroke(moduleColor.opacity(0.8), lineWidth: 1)
                            .frame(width: moduleSize.width * 0.6, height: moduleSize.height * 0.6)
                    )
            case .touchpad:
                RoundedRectangle(cornerRadius: 3)
                    .fill(moduleColor.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(moduleColor.opacity(0.6), lineWidth: 1)
                    )
                    .frame(width: moduleSize.width, height: moduleSize.height)
            default:
                Circle()
                    .fill(moduleColor.opacity(0.7))
                    .frame(width: moduleSize.width, height: moduleSize.height)
            }
        }
    }
}

struct PresetPreviewGridPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 12
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(Color(UIColor.secondarySystemBackground).opacity(0.3)), lineWidth: 0.5)
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
