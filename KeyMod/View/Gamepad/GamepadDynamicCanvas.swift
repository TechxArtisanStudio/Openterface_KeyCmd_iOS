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

    @State private var moduleDragOffsets: [String: CGSize] = [:]
    @State private var moduleBaseOffsets: [String: CGSize] = [:]
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
                    moduleRenderer(for: module, in: geometry.size)
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

    // MARK: - Module Renderer

    @ViewBuilder
    private func moduleRenderer(for module: GamepadModule, in size: CGSize) -> some View {
        let x = CGFloat(module.anchorX) * size.width + (moduleDragOffsets[module.id]?.width ?? 0)
        let y = CGFloat(module.anchorY) * size.height + (moduleDragOffsets[module.id]?.height ?? 0)
        let layoutScale = max(0.35, min(1.35, min(size.width, size.height) / 800.0))

        GamepadModuleView(
            module: module,
            globalSettings: document.layout,
            keyboardManager: keyboardManager,
            mouseManager: mouseManager,
            turboEngine: turboEngine,
            isEditMode: isEditMode,
            isPositionEditMode: isPositionEditMode,
            isKeyMappingMode: isKeyMappingMode,
            layoutScale: layoutScale,
            canvasSize: size,
            onModulePress: handleModulePress,
            onModuleRelease: handleModuleRelease,
            onModuleConfig: handleModuleConfig
        )
        .position(x: x, y: y)
        .gesture(
            isEditMode ? positionEditGesture(for: module, size: size) : nil
        )
    }

    // MARK: - Position Edit Gesture

    private func positionEditGesture(for module: GamepadModule, size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                moduleDragOffsets[module.id] = CGSize(width: dx, height: dy)
            }
            .onEnded { value in
                // TODO: Save new anchor position if needed
                moduleDragOffsets[module.id] = nil
            }
    }

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
