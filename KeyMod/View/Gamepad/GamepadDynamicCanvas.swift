//
//  GamepadDynamicCanvas.swift
//  KeyMod
//
//  Core dynamic layout renderer — renders modules from a GamepadPresetDocument.
//  Uses GeometryReader + ZStack + ForEach for schema-driven positioning.
//

import SwiftUI

struct GamepadDynamicCanvas: View {
    @Binding var document: GamepadPresetDocument
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var mouseManager: MouseManager
    @ObservedObject var backgroundManager: GamepadBackgroundManager
    @StateObject private var turboEngine: TurboEngine
    let isEditMode: Bool
    let isPositionEditMode: Bool
    let isKeyMappingMode: Bool
    var onSaveDocument: () -> Void = {}

    // Drag state is now local to each DraggableModuleWrapper via @GestureState
    @State private var showModuleConfig = false
    @State private var configModuleId = ""

    init(
        document: Binding<GamepadPresetDocument>,
        keyboardManager: KeyboardManager,
        mouseManager: MouseManager,
        backgroundManager: GamepadBackgroundManager,
        isEditMode: Bool,
        isPositionEditMode: Bool,
        isKeyMappingMode: Bool,
        onSaveDocument: @escaping () -> Void = {}
    ) {
        self._document = document
        self.keyboardManager = keyboardManager
        self.mouseManager = mouseManager
        self.backgroundManager = backgroundManager
        self.isEditMode = isEditMode
        self.isPositionEditMode = isPositionEditMode
        self.isKeyMappingMode = isKeyMappingMode
        self.onSaveDocument = onSaveDocument
        _turboEngine = StateObject(wrappedValue: TurboEngine(keyboardManager: keyboardManager))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                GamepadBackgroundRenderer(manager: backgroundManager)

                // Modules sorted by zIndex
                ForEach(sortedModules) { module in
                    DraggableModuleWrapper(
                        document: $document,
                        module: module,
                        canvasSize: geometry.size,
                        isEditMode: isEditMode,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        keyboardManager: keyboardManager,
                        mouseManager: mouseManager,
                        turboEngine: turboEngine,
                        onModulePress: handleModulePress,
                        onModuleRelease: handleModuleRelease,
                        onModuleConfig: handleModuleConfig,
                        onSaveDocument: onSaveDocument
                    )
                }
            }
        }
        .onDisappear {
            turboEngine.stop()
            keyboardManager.releaseAllKeys()
            mouseManager.handleDragEnded()
        }
        .sheet(isPresented: $showModuleConfig) {
            if let module = document.modules.first(where: { $0.id == configModuleId }) {
                ModuleConfigSheet(
                    document: $document,
                    module: module,
                    isPresented: $showModuleConfig
                )
                .onDisappear {
                    onSaveDocument()
                }
            }
        }
    }

    // MARK: - Module Sorting

    private var sortedModules: [GamepadModule] {
        document.modules.sorted { $0.zIndex < $1.zIndex }
    }

    // MARK: - Module Sorting (moduleRenderer moved to DraggableModuleWrapper below)

    // MARK: - Event Handlers

    private func handleModulePress(_ moduleId: String, direction: String?) {
        if let module = document.modules.first(where: { $0.id == moduleId }) {
            if let dir = direction {
                // D-pad direction press
                let key = dpadDirectionKey(dir)
                if !key.isEmpty {
                    keyboardManager.handleKeyDown(key)
                }
            } else if let key = derivedKey(for: module), !key.isEmpty {
                if isMouseAction(key) {
                    handleMouseAction(key)
                } else if module.turboEnabled {
                    turboEngine.start(key: key, config: TurboConfig(
                        enabled: true,
                        intervalMs: module.turboIntervalMs ?? 80,
                        initialDelayMs: module.turboInitialDelayMs ?? 400
                    ))
                } else if module.hasGestureLock {
                    keyboardManager.handleKeyDown(key)
                } else {
                    keyboardManager.handleKeyDown(key)
                }
            }
        }
    }

    private func handleModuleRelease(_ moduleId: String, direction: String?) {
        if let module = document.modules.first(where: { $0.id == moduleId }) {
            if let dir = direction {
                let key = dpadDirectionKey(dir)
                if !key.isEmpty {
                    keyboardManager.handleKeyUp(key)
                }
            } else if let key = derivedKey(for: module), !key.isEmpty {
                // If turbo is running, stop it; otherwise release the key normally
                if turboEngine.isActive {
                    turboEngine.stop()
                } else if !isMouseAction(key) {
                    keyboardManager.handleKeyUp(key)
                }
            }
        }
    }

    private func handleModuleConfig(_ moduleId: String) {
        configModuleId = moduleId
        showModuleConfig = true
    }

    // MARK: - Helpers

    private func derivedKey(for module: GamepadModule) -> String? {
        if let key = module.derivedKey, !key.isEmpty {
            return key
        }
        if let hidKey = module.hidKey {
            return hidKeyToKeyName(hidKey)
        }
        return nil
    }

    private func dpadDirectionKey(_ direction: String) -> String {
        return direction // "Up", "Down", "Left", "Right"
    }

    private func isMouseAction(_ action: String) -> Bool {
        let mouseActions = ["Left Click", "Right Click", "Double Click", "Drag Toggle", "Scroll Up", "Scroll Down"]
        return mouseActions.contains(action)
    }

    private func handleMouseAction(_ action: String) {
        switch action {
        case "Left Click": mouseManager.handleClick()
        case "Right Click": mouseManager.handleRightClick()
        case "Double Click": mouseManager.handleDoubleClick()
        case "Drag Toggle": mouseManager.handleDragModeToggle()
        case "Scroll Up": mouseManager.handleScroll(deltaX: 0, deltaY: 1)
        case "Scroll Down": mouseManager.handleScroll(deltaX: 0, deltaY: -1)
        default: break
        }
    }

    private func hidKeyToKeyName(_ hidKey: Int) -> String {
        switch hidKey {
        case 4: return "A"; case 5: return "B"; case 6: return "C"; case 7: return "D"
        case 8: return "E"; case 9: return "F"; case 10: return "G"; case 11: return "H"
        case 12: return "I"; case 13: return "J"; case 14: return "K"; case 15: return "L"
        case 16: return "M"; case 17: return "N"; case 18: return "O"; case 19: return "P"
        case 20: return "Q"; case 21: return "R"; case 22: return "S"; case 23: return "T"
        case 24: return "U"; case 25: return "V"; case 26: return "W"; case 27: return "X"
        case 28: return "Y"; case 29: return "Z"
        case 40: return "Enter"; case 41: return "Escape"; case 42: return "Backspace"
        case 43: return "Tab"; case 44: return "Space"
        case 80: return "Right"; case 81: return "Left"
        case 82: return "Down"; case 83: return "Up"
        case 224: return "Ctrl"; case 225: return "Shift"
        case 226: return "Alt"; case 227: return "Cmd"
        default: return ""
        }
    }
}

// MARK: - DraggableModuleWrapper

/// Per-module drag wrapper.  The drag state lives in `DraggingOverlay` so
/// only that sub-view re-renders during a drag — the parent canvas and its
/// siblings stay completely still, preventing gesture interruption.
private struct DraggableModuleWrapper: View {
    @Binding var document: GamepadPresetDocument
    let module: GamepadModule
    let canvasSize: CGSize
    let isEditMode: Bool
    let isPositionEditMode: Bool
    let isKeyMappingMode: Bool
    let keyboardManager: KeyboardManager
    let mouseManager: MouseManager
    let turboEngine: TurboEngine
    let onModulePress: (String, String?) -> Void
    let onModuleRelease: (String, String?) -> Void
    let onModuleConfig: (String) -> Void
    let onSaveDocument: () -> Void

    var body: some View {
        let layoutScale = max(0.35, min(1.35, min(canvasSize.width, canvasSize.height) / 800.0))
        let moduleSize = self.moduleSize(layoutScale: layoutScale)
        let baseX = CGFloat(module.anchorX) * canvasSize.width
        let baseY = CGFloat(module.anchorY) * canvasSize.height

        let moduleContent = GamepadModuleView(
            module: module,
            globalSettings: document.layout,
            keyboardManager: keyboardManager,
            mouseManager: mouseManager,
            turboEngine: turboEngine,
            isEditMode: isEditMode,
            isPositionEditMode: isPositionEditMode,
            isKeyMappingMode: isKeyMappingMode,
            showSettingsButton: false,
            layoutScale: layoutScale,
            canvasSize: canvasSize,
            onModulePress: onModulePress,
            onModuleRelease: onModuleRelease,
            onModuleConfig: onModuleConfig
        )
        .allowsHitTesting(!isEditMode)

        let wrapper = ZStack {
            if isEditMode {
                Color.clear
                    .contentShape(Rectangle())
            }
            moduleContent
        }
        .frame(width: moduleSize.width, height: moduleSize.height)
        .overlay(alignment: .topTrailing) {
            if isEditMode {
                Button { onModuleConfig(module.id) } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }

        // Position the wrapper at its base location using .position.
        // .position moves both the visual AND the hit area together,
        // so the gesture stays anchored to the finger throughout the drag.
        if isEditMode {
            DraggingOverlay(
                document: $document,
                baseX: baseX,
                baseY: baseY,
                canvasSize: canvasSize,
                module: module,
                onSaveDocument: onSaveDocument,
                content: { wrapper }
            )
        } else {
            wrapper
                .position(x: baseX, y: baseY)
        }
    }

    private func moduleSize(layoutScale: CGFloat) -> CGSize {
        switch module.type {
        case .button:
            let baseRadius = 100.0 * layoutScale * CGFloat(module.scale)
            let width = baseRadius * 2 * CGFloat(module.buttonWidthRatio)
            let height = baseRadius * 2 * CGFloat(module.buttonHeightRatio)
            return CGSize(width: width, height: height)

        case .dpad, .analogStick:
            let baseRadius = 180.0 * layoutScale * CGFloat(module.scale)
            return CGSize(width: baseRadius * 2, height: baseRadius * 2)

        case .scrollStrip:
            return CGSize(
                width: CGFloat(module.widthNorm ?? 0.10) * canvasSize.width,
                height: CGFloat(module.heightNorm ?? 0.36) * canvasSize.height
            )

        case .touchpad:
            return CGSize(
                width: CGFloat(module.widthNorm ?? 0.35) * canvasSize.width,
                height: CGFloat(module.heightNorm ?? 0.25) * canvasSize.height
            )

        case .mouseButton:
            let baseRadius = 52.0 * layoutScale * CGFloat(module.scale)
            return CGSize(width: baseRadius * 2, height: baseRadius * 2)

        case .shoulder, .trigger:
            let sw = 108.0 * layoutScale * CGFloat(module.scale)
            let sh = 34.0 * layoutScale * CGFloat(module.scale)
            return CGSize(width: sw, height: sh)
        }
    }
}

/// Isolated drag layer — mirrors Android's `onTouchEvent` approach:
///
/// Android: single `onTouchEvent` on the View → checks `componentBounds` → mutates `anchorX/Y` → `invalidate()`.
/// Here: ONE `DragGesture` on the OUTER ZStack so NOTHING can intercept touches (unlike the previous
/// approach with a Rectangle behind content in a ZStack, where content still received touches first).
///
/// State flow:
/// 1. `onChanged` captures start position on first call, tracks translation via `@State` (not `@GestureState`)
/// 2. Position = module.anchor * canvasSize + translation during drag
/// 3. `onEnded` writes normalized anchor back to document → triggers SwiftUI re-render via `@Binding`
/// 4. New `DraggingOverlay` instance created from updated `module`, position stable
private struct DraggingOverlay<Content: View>: View {
    @Binding var document: GamepadPresetDocument
    let baseX: CGFloat
    let baseY: CGFloat
    let canvasSize: CGSize
    let module: GamepadModule
    let onSaveDocument: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGSize = .zero
    @State private var dragStartX: CGFloat = 0
    @State private var dragStartY: CGFloat = 0
    @State private var isDragging: Bool = false

    var body: some View {
        let currentBaseX = isDragging ? dragStartX : CGFloat(module.anchorX) * canvasSize.width
        let currentBaseY = isDragging ? dragStartY : CGFloat(module.anchorY) * canvasSize.height

        let dragGesture = DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isDragging {
                    dragStartX = CGFloat(module.anchorX) * canvasSize.width
                    dragStartY = CGFloat(module.anchorY) * canvasSize.height
                    isDragging = true
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                let finalX = currentBaseX + value.translation.width
                let finalY = currentBaseY + value.translation.height
                let normX = max(0, min(1, Double(finalX / canvasSize.width)))
                let normY = max(0, min(1, Double(finalY / canvasSize.height)))
                if let index = document.modules.firstIndex(where: { $0.id == module.id }) {
                    document.modules[index].anchorX = normX
                    document.modules[index].anchorY = normY
                }
                dragOffset = .zero
                isDragging = false
                onSaveDocument()
            }

        content()
            .position(
                x: currentBaseX + dragOffset.width,
                y: currentBaseY + dragOffset.height
            )
            .gesture(dragGesture)
    }
}
