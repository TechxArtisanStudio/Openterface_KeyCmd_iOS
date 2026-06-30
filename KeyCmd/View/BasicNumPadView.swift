//
//  BasicNumPadView.swift
//  KeyMod
//
//  Legacy numpad layout for Keyboard & Mouse (Basic) mode.
//  Kept for backward compatibility — Pro mode uses NumPadView (Android layout).
//

import SwiftUI

struct BasicNumPadView: View {
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var orientationManager: OrientationManager
    @ObservedObject private var themeManager = ThemeManager.shared

    private let sp: CGFloat = 8   // gap between keys
    private let pad: CGFloat = 8  // outer padding
    static let cameraSafeInset: CGFloat = 60  // Dynamic Island safe area in landscape

    // Match the base keyboard arrow key styling
    private static let functionKeyBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.18, alpha: 1.0)
            : UIColor(white: 0.94, alpha: 1.0)
    })
    private static let keyIconIdle = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.75, alpha: 1.0)
            : UIColor(white: 0.25, alpha: 1.0)
    })
    private static let keyIconPressed = Color.white

    /// Gradient background for keys: grey → dark grey → grey (middle stop at 45%)
    /// 45-degree angle from top-right to bottom-left
    private static let keyBackground = LinearGradient(
        gradient: Gradient(colors: [
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(white: 0.25, alpha: 1.0)
                    : UIColor(white: 0.55, alpha: 1.0)
            }),
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(white: 0.20, alpha: 1.0)
                    : UIColor(white: 0.42, alpha: 1.0)
            }),
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(white: 0.18, alpha: 1.0)
                    : UIColor(white: 0.45, alpha: 1.0)
            })
        ]),
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )

    var body: some View {
        GeometryReader { geo in
            if orientationManager.isLandscape {
                landscapeLayout(geo: geo)
            } else {
                portraitLayout(geo: geo)
            }
        }
    }

    // MARK: - Landscape (8 cols × 5 rows)

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        // Account for camera safe area (Dynamic Island) on the appropriate side
        let cameraInset = orientationManager.cameraOnRight
            ? max(geo.safeAreaInsets.trailing, Self.cameraSafeInset)
            : max(geo.safeAreaInsets.leading, Self.cameraSafeInset)
        let availableWidth = geo.size.width - cameraInset - 2 * pad
        let cw = (availableWidth - 7 * sp) / 8
        let rh = (geo.size.height - 2 * pad - 4 * sp) / 5

        VStack(alignment: .leading, spacing: sp) {
            // Row 1
            HStack(spacing: sp) {
                k("Escape",         "ESC",    w: cw,      h: rh)
                k("Tab",            "TAB",    w: cw,      h: rh)
                k("Backspace",      "BKSP", w: cw * 2 + sp, h: rh)
                k("NumLock",        "Num Lk",  w: cw,      h: rh)
                k("NumpadSlash",    "/",      w: cw,      h: rh)
                k("NumpadAsterisk", "*",      w: cw,      h: rh)
                k("NumpadMinus",    "-",      w: cw,      h: rh)
            }

            // Rows 2–3 with + spanning vertically in col 8
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    HStack(spacing: sp) {
                        k("PrintScreen", "Prt Sr", w: cw, h: rh)
                        k("Insert",      "Ins",    w: cw, h: rh)
                        k("Pause",       "Pause",  w: cw, h: rh)
                        k("PgUp",        "Pg Up",   w: cw, h: rh)
                        k("Numpad7",     "7",      w: cw, h: rh)
                        k("Numpad8",     "8",      w: cw, h: rh)
                        k("Numpad9",     "9",      w: cw, h: rh)
                    }
                    HStack(spacing: sp) {
                        k("ScrollLock", "Scr Lk", w: cw, h: rh)
                        k("Home",       "Home",   w: cw, h: rh)
                        k("End",        "End",    w: cw, h: rh)
                        k("PgDn",       "Pg Dn",   w: cw, h: rh)
                        k("Numpad4",    "4",      w: cw, h: rh)
                        k("Numpad5",    "5",      w: cw, h: rh)
                        k("Numpad6",    "6",      w: cw, h: rh)
                    }
                }
                k("NumpadPlus", "+", w: cw, h: rh * 2 + sp)
            }

            // Rows 4–5 with Enter spanning vertically in col 8
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    HStack(spacing: sp) {
                        k("Delete",    "DEL", w: cw, h: rh)
                        arrowKey("Up", "up", w: cw, h: rh, iconScale: 1.56)
                        k("Backspace", "BKSP", w: cw, h: rh)
                        doubleZero(w: cw, h: rh)
                        k("Numpad1",   "1",   w: cw, h: rh)
                        k("Numpad2",   "2",   w: cw, h: rh)
                        k("Numpad3",   "3",   w: cw, h: rh)
                    }
                    HStack(spacing: sp) {
                        arrowKey("Left",  "left",  w: cw,      h: rh, iconScale: 1.56)
                        arrowKey("Down",  "down",  w: cw,      h: rh, iconScale: 1.56)
                        arrowKey("Right", "right", w: cw,      h: rh, iconScale: 1.56)
                        k("NumpadEquals", "=", w: cw,      h: rh)
                        numpadZero(w: cw * 2 + sp, h: rh, iconScale: 0.72)
                        k("NumpadDot",    ".", w: cw,      h: rh)
                    }
                }
                k("NumpadEnter", "Enter", w: cw, h: rh * 2 + sp)
            }
        }
        .padding(pad)
        // Camera-side safe area padding for Dynamic Island (matches keyboard view)
        .padding(.leading, !orientationManager.cameraOnRight ? max(geo.safeAreaInsets.leading, Self.cameraSafeInset) : 0)
        .padding(.trailing, orientationManager.cameraOnRight ? max(geo.safeAreaInsets.trailing, Self.cameraSafeInset) : 0)
    }

    // MARK: - Portrait (5 cols × 8 rows)

    @ViewBuilder
    private func portraitLayout(geo: GeometryProxy) -> some View {
        let cw = (geo.size.width  - 2 * pad - 4 * sp) / 5
        let rh = (geo.size.height - 2 * pad - 7 * sp) / 8
        let numRh = rh * 1.25  // Numpad keys 25% taller

        VStack(spacing: sp) {
            // Rows 1–2 (ESC spans TAB+Scroll combined height)
            HStack(alignment: .top, spacing: sp) {
                k("Escape", "ESC", w: cw, h: rh + sp)
                VStack(spacing: sp) {
                    HStack(spacing: sp) {
                        k("Tab",       "TAB",    w: cw, h: rh / 2)
                        k("Delete",    "DEL",    w: cw, h: rh / 2)
                        arrowKey("Up",   "up",    w: cw, h: rh / 2)
                        k("Backspace", "BKSP", w: cw, h: rh / 2)
                    }
                    HStack(spacing: sp) {
                        k("ScrollLock", "Scr Lk", w: cw, h: rh / 2)
                        arrowKey("Left",  "left",  w: cw, h: rh / 2)
                        arrowKey("Down",  "down",  w: cw, h: rh / 2)
                        arrowKey("Right", "right", w: cw, h: rh / 2)
                    }
                }
            }
                        // Row 3
            HStack(spacing: sp) {
                k("PrintScreen",  "Prt Sr", w: cw, h: rh * 0.9)
                k("Pause",        "Pause", w: cw, h: rh * 0.9)
                k("Home",         "Home",  w: cw, h: rh * 0.9)
                k("End",          "End",   w: cw, h: rh * 0.9)
                k("NumpadEquals", "=",     w: cw, h: rh * 0.9)
            }
            // Row 4
            HStack(spacing: sp) {
                k("PgUp",           "Pg Up",  w: cw, h: rh * 0.9)
                k("NumLock",        "Num Lk", w: cw, h: rh * 0.9)
                k("NumpadSlash",    "/",     w: cw, h: rh * 0.9)
                k("NumpadAsterisk", "*",     w: cw, h: rh * 0.9)
                k("NumpadMinus",    "-",     w: cw, h: rh * 0.9)
            }

            // Rows 5–6 with + spanning vertically in col 5 (numpad keys 25% taller)
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    HStack(spacing: sp) {
                        k("PgDn",    "Pg Dn", w: cw, h: numRh)
                        k("Numpad7", "7",    w: cw, h: numRh)
                        k("Numpad8", "8",    w: cw, h: numRh)
                        k("Numpad9", "9",    w: cw, h: numRh)
                    }
                    HStack(spacing: sp) {
                        k("Insert",  "Ins", w: cw, h: numRh)
                        k("Numpad4", "4",   w: cw, h: numRh)
                        k("Numpad5", "5",   w: cw, h: numRh)
                        k("Numpad6", "6",   w: cw, h: numRh)
                    }
                }
                k("NumpadPlus", "+", w: cw, h: numRh * 2 + sp)
            }

            // Rows 7–8 with Enter spanning vertically in col 5 (numpad keys 25% taller)
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    HStack(spacing: sp) {
                        k("Backspace", "BKSP",  w: cw, h: numRh)
                        k("Numpad1",   "1",  w: cw, h: numRh)
                        k("Numpad2",   "2",  w: cw, h: numRh)
                        k("Numpad3",   "3",  w: cw, h: numRh)
                    }
                    HStack(spacing: sp) {
                        doubleZero(w: cw,      h: numRh)
                        numpadZero(w: cw * 2 + sp, h: numRh)
                        k("NumpadDot", ".", w: cw,      h: numRh)
                    }
                }
                k("NumpadEnter", "Enter", w: cw, h: numRh * 2 + sp)
            }
        }
        .padding(pad)
    }

    // MARK: - Key Buttons

    @ViewBuilder
    private func k(_ key: String, _ display: String, w: CGFloat, h: CGFloat) -> some View {
        let fontSize = min(min(w, h) * 0.38, 16)
        KeyPressButton(
            onPress: {
                HapticFeedbackManager.shared.triggerButtonPress()
                keyboardManager.handleKeyDown(key)
            },
            onRelease: { keyboardManager.handleKeyUp(key) }
        ) { isPressed in
            Text(display)
                .font(.system(size: fontSize, weight: .semibold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundColor(isPressed ? .white : .primary)
                .frame(width: w, height: h)
                .background {
                    if isPressed {
                        themeManager.accentColor
                    } else {
                        Self.keyBackground
                    }
                }
                .cornerRadius(6)
        }
    }

    /// "00" key — sends two Numpad0 presses in quick succession.
    @ViewBuilder
    private func doubleZero(w: CGFloat, h: CGFloat) -> some View {
        let fontSize = min(min(w, h) * 0.38, 16)
        KeyPressButton(
            onPress: {
                HapticFeedbackManager.shared.triggerButtonPress()
                keyboardManager.handleKeyDown("Numpad0")
                keyboardManager.handleKeyUp("Numpad0")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    keyboardManager.handleKeyDown("Numpad0")
                    keyboardManager.handleKeyUp("Numpad0")
                }
            },
            onRelease: {}
        ) { isPressed in
            Text("00")
                .font(.system(size: fontSize, weight: .semibold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundColor(isPressed ? .white : .primary)
                .frame(width: w, height: h)
                .background {
                    if isPressed {
                        themeManager.accentColor
                    } else {
                        Self.keyBackground
                    }
                }
                .cornerRadius(6)
        }
    }

    /// Arrow key with KeyboardArrow shape (matches base keyboard style)
    @ViewBuilder
    private func arrowKey(_ key: String, _ direction: String, w: CGFloat, h: CGFloat, iconScale: CGFloat = 1.0) -> some View {
        let dir: KeyboardArrow.Direction = {
            switch direction {
            case "up": return .up
            case "down": return .down
            case "left": return .left
            case "right": return .right
            default: return .up
            }
        }()
        let iconSize = min(w, h) * 0.4 * iconScale
        let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
        KeyPressButton(
            onPress: {
                HapticFeedbackManager.shared.triggerButtonPress()
                repeatMode ? keyboardManager.startKeyRepeat(key) : keyboardManager.handleKeyDown(key)
            },
            onRelease: {
                repeatMode ? keyboardManager.stopKeyRepeat() : keyboardManager.handleKeyUp(key)
            },
            keyPreview: key
        ) { isPressed in
            KeyboardArrow(direction: dir)
                .fill(isPressed ? Self.keyIconPressed : Self.keyIconIdle)
                .frame(width: iconSize, height: iconSize)
                .frame(width: w, height: h)
                .background {
                    if isPressed {
                        themeManager.accentColor
                    } else {
                        Self.keyBackground
                    }
                }
                .cornerRadius(6)
        }
    }

    /// "0" key with Openterface wordmark (matches base keyboard space key style)
    @ViewBuilder
    private func numpadZero(w: CGFloat, h: CGFloat, iconScale: CGFloat = 1.0) -> some View {
        KeyPressButton(
            onPress: {
                HapticFeedbackManager.shared.triggerButtonPress()
                keyboardManager.handleKeyDown("Numpad0")
            },
            onRelease: { keyboardManager.handleKeyUp("Numpad0") },
            keyPreview: "0"
        ) { isPressed in
            Image("openterface_wordmark")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: w * 0.6 * iconScale)
                .frame(width: w, height: h, alignment: .center)
                .background {
                    if isPressed {
                        themeManager.accentColor
                    } else {
                        Self.keyBackground
                    }
                }
                .cornerRadius(6)
                .foregroundColor(isPressed ? .white : .primary)
        }
    }
}
