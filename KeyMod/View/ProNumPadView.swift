//
//  ProNumPadView.swift
//  KeyMod
//
//  Pro numpad layout: LMR strip left of touchpad, numpad grid below.
//  Portrait only — matches Android addExtraPortraitKeys() proportional sizing.
//

import SwiftUI

struct ProNumPadView: View {
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var mouseManager: MouseManager
    @StateObject private var pointerTipState = PointerTipState()
    @ObservedObject private var prefs = KmProPrefs.shared

    @State private var fnLocked = false
    @State private var pointerMoving = false

    private let sp: CGFloat = 2    // 2dp gap between keys (matching Android KEY_OUTER_MARGIN_DP)
    private let lmrWidth: CGFloat = 100

    private var macOS: Bool { AISettings.shared.targetOS == .macOS }

    // Android fragment_composite.xml weights:
    // touchpad_section=1.25, keyboard_slot=2.15 → total=3.40
    // touchpad = 1.25/3.40 ≈ 36.76% of total height (Android)
    // We use 0.30 to give touchpad slightly less space, more room for keys
    private let touchpadFraction: CGFloat = 0.30

    // Android row weights: rows 0-2 → 0.5f, rows 3-6 → 1.0f
    // Total = 3×0.5 + 4×1.0 = 5.5
    private let compactWeight: CGFloat = 0.5
    private let fullWeight: CGFloat = 1.0
    private let totalWeight: CGFloat = 5.5

    // MARK: - Mouse button state
    private var isLHeld: Bool { (mouseManager.heldButtons & 0x01) != 0 || mouseManager.isSelectMode || (mouseManager.clickFlash & 0x01) != 0 }
    private var isMHeld: Bool { (mouseManager.heldButtons & 0x04) != 0 || (mouseManager.clickFlash & 0x04) != 0 }
    private var isRHeld: Bool { (mouseManager.heldButtons & 0x02) != 0 || (mouseManager.clickFlash & 0x02) != 0 }
    private var touchpadStatusText: String {
        var parts: [String] = []
        if mouseManager.isSelectMode { parts.append("drag") }
        if (mouseManager.heldButtons & 0x01) != 0 { parts.append("L held") }
        if (mouseManager.heldButtons & 0x04) != 0 { parts.append("M held") }
        if (mouseManager.heldButtons & 0x02) != 0 { parts.append("R held") }
        let buttons = parts.isEmpty ? "buttons up" : parts.joined(separator: " + ")
        return "\(buttons) · \(pointerMoving ? "moving" : "idle")"
    }

    var body: some View {
        GeometryReader { geo in
            let tpH = geo.size.height * touchpadFraction
            let gridH = geo.size.height - tpH

            VStack(spacing: 0) {
                touchpadSection
                    .frame(height: tpH)

                numpadGrid(totalHeight: gridH)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Touchpad Section (LMR left + touchpad + scroll strip)

    private var touchpadSection: some View {
        HStack(spacing: 0) {
            VStack(spacing: 1) {
                lmrButton("L", held: isLHeld) { mouseManager.handleClick() }
                lmrButton("M", held: isMHeld) { mouseManager.handleMiddleClick() }
                lmrButton("R", held: isRHeld) { mouseManager.handleRightClick() }
            }
            .padding(1)
            .frame(width: lmrWidth)

            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    TouchpadView(
                        mouseManager: mouseManager,
                        pointerTipState: pointerTipState,
                        padClickDragGesturesEnabled: prefs.padClickDragGesturesEnabled,
                        onPointerMoving: { moving in pointerMoving = moving }
                    )
                    ProTouchpadScrollStripView(mouseManager: mouseManager, labelFontSize: 7)
                        .frame(width: 80)
                }
                .background(mouseManager.isSelectMode ? Color.blue.opacity(0.18) : Color.clear)

                Text(touchpadStatusText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.85))
                    .cornerRadius(5)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Numpad Grid

    @ViewBuilder
    private func numpadGrid(totalHeight: CGFloat) -> some View {
        // Android GridLayout has no container padding — rows fill the full height
        // with only inter-row gaps between them.
        let rowSpacingTotal = sp * 6  // 6 gaps between 7 rows
        let usableH = totalHeight - rowSpacingTotal

        let compactH = usableH * compactWeight / totalWeight
        let fullH = usableH * fullWeight / totalWeight
        let rowHeights: [CGFloat] = [compactH, compactH, compactH, fullH, fullH, fullH, fullH]
        let tallH = fullH * 2 + sp  // tall key spans two rows + one gap

        GeometryReader { geo in
            let W = geo.size.width
            let col4W = (W - 3 * sp) / 4  // all rows: 4 equal-width keys

            VStack(spacing: sp) {
                // Row 0 (compact): CUT PASTE COPY ALL
                HStack(spacing: sp) {
                    shortcutKey("CUT",  icon: "scissors",              combo: macOS ? ["Cmd"] : ["Ctrl"], key: "X", h: rowHeights[0], w: col4W)
                    shortcutKey("PASTE", icon: "clipboard",            combo: macOS ? ["Cmd"] : ["Ctrl"], key: "V", h: rowHeights[0], w: col4W)
                    shortcutKey("COPY",  icon: "doc.on.doc",           combo: macOS ? ["Cmd"] : ["Ctrl"], key: "C", h: rowHeights[0], w: col4W)
                    shortcutKey("ALL",   icon: "text.badge.checkmark", combo: macOS ? ["Cmd"] : ["Ctrl"], key: "A", h: rowHeights[0], w: col4W)
                }

                // Row 1 (compact): ESC/NUM, #/|, UNDO/REDO, BKSP
                HStack(spacing: sp) {
                    toggleKey(off: "ESC",  on: "NUM",  onAction: { keyboardManager.handleKeyPress("NumLock") },
                                                        offAction: { keyboardManager.handleKeyPress("Escape") }, h: rowHeights[1], w: col4W)
                    toggleKey(off: "#",    on: "|",    onAction: { keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: "Backslash") },
                                                        offAction: { keyboardManager.handleTextInput("#") }, h: rowHeights[1], w: col4W)
                    shortcutKey(fnLocked ? "REDO" : "UNDO",
                                icon: fnLocked ? "arrow.uturn.forward" : "arrow.uturn.backward",
                                combo: fnLocked ? (macOS ? ["Cmd", "Shift"] : ["Ctrl"]) : (macOS ? ["Cmd"] : ["Ctrl"]),
                                key: fnLocked ? (macOS ? "Z" : "Y") : "Z", h: rowHeights[1], w: col4W)
                    repeatKey("BKSP", key: "Backspace", h: rowHeights[1], w: col4W)
                }

                // Row 2 (compact): =/£, Space/€, /¥, */$  (4 equal keys)
                HStack(spacing: sp) {
                    toggleKey(off: "=",    on: "£", onAction: { keyboardManager.handleKeyCombo(modifiers: ["Alt"], key: "NumpadEquals") },
                                                 offAction: { keyboardManager.handleKeyPress("NumpadEquals") }, h: rowHeights[2], w: col4W)
                    toggleKey(off: "Space", on: "€", onAction: { keyboardManager.handleKeyCombo(modifiers: ["Alt", "Shift"], key: "NumpadEquals") },
                                                  offAction: { keyboardManager.handleKeyPress("Space") }, h: rowHeights[2], w: col4W)
                    toggleKey(off: "/",    on: "¥", onAction: { keyboardManager.handleKeyCombo(modifiers: ["Alt"], key: "NumpadSlash") },
                                                offAction: { keyboardManager.handleKeyPress("NumpadSlash") }, h: rowHeights[2], w: col4W)
                    toggleKey(off: "*",    on: "$", onAction: { keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: "NumpadAsterisk") },
                                                offAction: { keyboardManager.handleKeyPress("NumpadAsterisk") }, h: rowHeights[2], w: col4W)
                }

                // Row 3 (full): 7/HOME  8/↑  9/PGUP  |  -/% (top half) + +/DEL (bottom half)
                halfSplitRightRow(leftKeys: [
                    toggleKey(off: "7", on: "HOME", onAction: { keyboardManager.handleKeyPress("Home") }, offAction: { keyboardManager.handleKeyPress("Numpad7") }, h: fullH, w: col4W),
                    toggleKey(off: "8", on: "↑",   onAction: { keyboardManager.handleKeyPress("Up") }, offAction: { keyboardManager.handleKeyPress("Numpad8") }, h: fullH, w: col4W),
                    toggleKey(off: "9", on: "PGUP", onAction: { keyboardManager.handleKeyPress("PgUp") }, offAction: { keyboardManager.handleKeyPress("Numpad9") }, h: fullH, w: col4W),
                ],
                topRight: AnyView(miniKey(fnLocked ? "%" : "-",
                    action: fnLocked ? { keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: "NumpadMinus") } : { keyboardManager.handleKeyPress("NumpadMinus") },
                    h: (fullH - sp) / 2, w: col4W)),
                bottomRight: AnyView(miniKey(fnLocked ? "DEL" : "+",
                    action: fnLocked ? { keyboardManager.handleKeyPress("Delete") } : { keyboardManager.handleKeyPress("NumpadPlus") },
                    h: (fullH - sp) / 2, w: col4W)),
                rowH: fullH, keyW: col4W)

                // Row 4 (full): 4/←  5/INS  6/→  TAB
                HStack(spacing: sp) {
                    toggleKey(off: "4", on: "←",   onAction: { keyboardManager.handleKeyPress("Left") }, offAction: { keyboardManager.handleKeyPress("Numpad4") }, h: fullH, w: col4W)
                    toggleKey(off: "5", on: "INS", onAction: { keyboardManager.handleKeyPress("Insert") }, offAction: { keyboardManager.handleKeyPress("Numpad5") }, h: fullH, w: col4W)
                    toggleKey(off: "6", on: "→",   onAction: { keyboardManager.handleKeyPress("Right") }, offAction: { keyboardManager.handleKeyPress("Numpad6") }, h: fullH, w: col4W)
                    if fnLocked {
                        shortcutKey("SAVE", icon: "square.and.arrow.down",
                            combo: macOS ? ["Cmd"] : ["Ctrl"], key: "S", h: fullH, w: col4W, scale: 0.5)
                    } else {
                        miniKey("⇥", action: { keyboardManager.handleKeyPress("Tab") }, h: fullH, w: col4W, fontSize: 22)
                    }
                }

                // Row 5+6: END/↓/PGDN + tall ENTER (spans 2 rows)
                // Row 6 underneath: 切換/,/0
                twoRowSection(
                    rightTallKey: AnyView(tallKey(off: "ENTER", on: "ENTER",
                        onAction: { keyboardManager.handleKeyPress("NumpadEnter") },
                        offAction: { keyboardManager.handleKeyPress("NumpadEnter") },
                        h: tallH, w: col4W)),
                    rowH: fullH, keyW: col4W
                ) {
                    toggleKey(off: "1", on: "END",  onAction: { keyboardManager.handleKeyPress("End") }, offAction: { keyboardManager.handleKeyPress("Numpad1") }, h: fullH, w: col4W)
                    toggleKey(off: "2", on: "↓",    onAction: { keyboardManager.handleKeyPress("Down") }, offAction: { keyboardManager.handleKeyPress("Numpad2") }, h: fullH, w: col4W)
                    toggleKey(off: "3", on: "PGDN", onAction: { keyboardManager.handleKeyPress("PgDn") }, offAction: { keyboardManager.handleKeyPress("Numpad3") }, h: fullH, w: col4W)
                } bottomContent: {
                    fnToggleKey(h: fullH, w: col4W)
                    toggleKey(off: ".", on: ",",
                        onAction: { keyboardManager.handleTextInput(",") },
                        offAction: { keyboardManager.handleKeyPress("NumpadDot") },
                        h: fullH, w: col4W)
                    numpadButton("0", action: { keyboardManager.handleKeyPress("Numpad0") },
                        h: fullH, w: col4W)
                }
            }
        }
        .frame(height: totalHeight)
    }

    /// A row where the right column is split into two half-height buttons.
    private func halfSplitRightRow<Content: View>(
        leftKeys: [Content],
        topRight: AnyView,
        bottomRight: AnyView,
        rowH: CGFloat,
        keyW: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // Left keys + invisible spacer for right column
            HStack(spacing: sp) {
                ForEach(leftKeys.indices, id: \.self) { leftKeys[$0] }
                Color.clear.frame(width: keyW, height: rowH)
            }

            // Top half button positioned at right column
            HStack(spacing: sp) {
                Color.clear.frame(width: keyW * 3 + sp * 2, height: (rowH - sp) / 2)
                topRight
            }

            // Bottom half button positioned at right column
            HStack(spacing: sp) {
                Color.clear.frame(width: keyW * 3 + sp * 2, height: (rowH - sp) / 2)
                bottomRight
            }
            .offset(y: (rowH + sp) / 2)
        }
    }

    /// A two-row section where the rightmost key spans both rows.
    private func twoRowSection<Content: View, BottomContent: View>(
        rightTallKey: AnyView,
        rowH: CGFloat,
        keyW: CGFloat,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomContent: () -> BottomContent
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // VStack sizes the ZStack correctly to 2*rowH + sp
            VStack(spacing: sp) {
                HStack(spacing: sp) {
                    content()
                    Color.clear.frame(width: keyW, height: rowH)
                }
                HStack(spacing: sp) {
                    bottomContent()
                    Color.clear.frame(width: keyW, height: rowH)
                }
            }

            // Tall ENTER key pinned to the right column, spanning both rows
            HStack(spacing: sp) {
                Color.clear.frame(width: keyW * 3 + sp * 2, height: 1)
                rightTallKey
            }
        }
    }

    // MARK: - Key Button Builders

    @ViewBuilder
    private func numpadButton(_ label: String, action: @escaping () -> Void, h: CGFloat, w: CGFloat) -> some View {
        Button(action: {
            HapticFeedbackManager.shared.triggerButtonPress()
            action()
        }) {
            Text(label)
                .font(.system(size: 17, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(9)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func shortcutKey(_ label: String, icon: String, combo: [String], key: String, h: CGFloat, w: CGFloat, scale: CGFloat = 1.0) -> some View {
        Button(action: {
            HapticFeedbackManager.shared.triggerButtonPress()
            keyboardManager.handleKeyCombo(modifiers: combo, key: key)
        }) {
            VStack(spacing: 1) {
                if let sysImg = iconToSystemImage(icon) {
                    Image(systemName: sysImg).font(.system(size: h * 0.35 * scale))
                }
                Text(label)
                    .font(.system(size: h * 0.25 * scale, weight: .medium))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(9)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func toggleKey(off: String, on: String, onAction: @escaping () -> Void, offAction: @escaping () -> Void, h: CGFloat, w: CGFloat) -> some View {
        let label = fnLocked ? on : off
        let action = fnLocked ? onAction : offAction
        Button(action: {
            HapticFeedbackManager.shared.triggerButtonPress()
            action()
        }) {
            Text(label)
                .font(.system(size: 17, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(9)
        }
        .buttonStyle(PlainButtonStyle())
        .id(label)
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func tallKey(off: String, on: String, onAction: @escaping () -> Void, offAction: @escaping () -> Void, h: CGFloat, w: CGFloat) -> some View {
        let label = fnLocked ? on : off
        let action = fnLocked ? onAction : offAction
        Button(action: {
            HapticFeedbackManager.shared.triggerButtonPress()
            action()
        }) {
            Text(label)
                .font(.system(size: 17, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(9)
        }
        .buttonStyle(PlainButtonStyle())
        .id(label)
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func repeatKey(_ label: String, key: String, h: CGFloat, w: CGFloat) -> some View {
        KeyPressButton(
            onPress: {
                HapticFeedbackManager.shared.triggerButtonPress()
                keyboardManager.handleKeyDown(key)
            },
            onRelease: { keyboardManager.handleKeyUp(key) }
        ) { isPressed in
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundColor(isPressed ? .white : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isPressed ? Color.blue.opacity(0.7) : Color(UIColor.tertiarySystemBackground))
                .cornerRadius(9)
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func miniKey(_ label: String, action: @escaping () -> Void, h: CGFloat, w: CGFloat, fontSize: CGFloat = 14) -> some View {
        Button(action: {
            HapticFeedbackManager.shared.triggerButtonPress()
            action()
        }) {
            Text(label)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(9)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func fnToggleKey(h: CGFloat, w: CGFloat) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { fnLocked.toggle() } }) {
            Image(systemName: fnLocked ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.swap")
                .resizable().scaledToFit()
                .frame(width: h * 0.28, height: h * 0.28)
                .foregroundColor(fnLocked ? .white : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(fnLocked ? Color.blue.opacity(0.7) : Color(UIColor.tertiarySystemBackground))
                .cornerRadius(9)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func lmrButton(_ label: String, held: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
        }
        .buttonStyle(LMRButtonStyle(held: held))
    }

    private struct LMRButtonStyle: ButtonStyle {
        var held: Bool = false
        func makeBody(configuration: Configuration) -> some View {
            let active = configuration.isPressed || held
            return configuration.label
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .background(active ? Color.blue.opacity(held ? 0.7 : 0.5) : Color(UIColor.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
                .foregroundColor(active ? .white : .primary)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }

    private func iconToSystemImage(_ icon: String) -> String? {
        switch icon {
        case "scissors": return "scissors"
        case "clipboard": return "clipboard"
        case "doc.on.doc": return "doc.on.doc"
        case "text.badge.checkmark": return "text.badge.checkmark"
        case "arrow.uturn.forward": return "arrow.uturn.forward"
        case "arrow.uturn.backward": return "arrow.uturn.backward"
        case "square.and.arrow.down": return "square.and.arrow.down"
        default: return nil
        }
    }
}
