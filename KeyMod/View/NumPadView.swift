import SwiftUI

struct NumPadView: View {
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var orientationManager: OrientationManager

    private let sp: CGFloat = 4   // gap between keys
    private let pad: CGFloat = 8  // outer padding

    var body: some View {
        GeometryReader { geo in
            if orientationManager.isLandscape {
                landscapeLayout(geo: geo)
            } else {
                portraitLayout(geo: geo)
            }
        }
    }

    // MARK: - Landscape (8 cols × 5 rows, left-aligned)
    //
    // Row 1: ESC  TAB  Backspace(2w)  NumLock  /  *  -
    // Row 2: Print  Ins  Pause  PgUp  7  8  9  ┐
    // Row 3: Scroll  Home  End  [ ]  4  5  6   +  (2-tall)
    // Row 4: Del  ↑  Backspace  00  1  2  3    ┐
    // Row 5: ←  ↓  →  =  0(2w)  .              Enter (2-tall)

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        // Fill available width: 8 columns + 7 gaps
        let cw = (geo.size.width - 2*pad - 7*sp) / 8
        let rh = (geo.size.height - 2*pad - 4*sp) / 5

        VStack(alignment: .leading, spacing: sp) {
                // Row 1
                HStack(spacing: sp) {
                    k("Escape",         "ESC",    w: cw,      h: rh)
                    k("Tab",            "TAB",    w: cw,      h: rh)
                    k("Backspace",      "⌫ Bksp", w: cw*2+sp, h: rh)
                    k("NumLock",        "NumLk",  w: cw,      h: rh)
                    k("NumpadSlash",    "/",      w: cw,      h: rh)
                    k("NumpadAsterisk", "*",      w: cw,      h: rh)
                    k("NumpadMinus",    "-",      w: cw,      h: rh)
                }

                // Rows 2–3 with + spanning vertically in col 8
                HStack(alignment: .top, spacing: sp) {
                    VStack(spacing: sp) {
                        // Row 2 (cols 1–7)
                        HStack(spacing: sp) {
                            k("PrintScreen", "Print",  w: cw, h: rh)
                            k("Insert",      "Ins",    w: cw, h: rh)
                            k("Pause",       "Pause",  w: cw, h: rh)
                            k("PgUp",        "PgUp",   w: cw, h: rh)
                            k("Numpad7",     "7",      w: cw, h: rh)
                            k("Numpad8",     "8",      w: cw, h: rh)
                            k("Numpad9",     "9",      w: cw, h: rh)
                        }
                        // Row 3 (cols 1–7)
                        HStack(spacing: sp) {
                            k("ScrollLock", "Scroll", w: cw, h: rh)
                            k("Home",       "Home",   w: cw, h: rh)
                            k("End",        "End",    w: cw, h: rh)
                            k("PgDn",       "PgDn",   w: cw, h: rh)
                            k("Numpad4",    "4",      w: cw, h: rh)
                            k("Numpad5",    "5",      w: cw, h: rh)
                            k("Numpad6",    "6",      w: cw, h: rh)
                        }
                    }
                    // Col 8: + (rows 2–3)
                    k("NumpadPlus", "+", w: cw, h: rh*2+sp)
                }

                // Rows 4–5 with Enter spanning vertically in col 8
                HStack(alignment: .top, spacing: sp) {
                    VStack(spacing: sp) {
                        // Row 4 (cols 1–7)
                        HStack(spacing: sp) {
                            k("Delete",    "Del", w: cw, h: rh)
                            k("Up",        "↑",   w: cw, h: rh)
                            k("Backspace", "⌫",   w: cw, h: rh)
                            doubleZero(w: cw, h: rh)
                            k("Numpad1",   "1",   w: cw, h: rh)
                            k("Numpad2",   "2",   w: cw, h: rh)
                            k("Numpad3",   "3",   w: cw, h: rh)
                        }
                        // Row 5 (cols 1–7)
                        HStack(spacing: sp) {
                            k("Left",         "←", w: cw,      h: rh)
                            k("Down",         "↓", w: cw,      h: rh)
                            k("Right",        "→", w: cw,      h: rh)
                            k("NumpadEquals", "=", w: cw,      h: rh)
                            k("Numpad0",      "0", w: cw*2+sp, h: rh)
                            k("NumpadDot",    ".", w: cw,      h: rh)
                        }
                    }
                    // Col 8: Enter (rows 4–5)
                    k("NumpadEnter", "Enter", w: cw, h: rh*2+sp)
                }
        }
        .padding(pad)
    }

    // MARK: - Portrait (5 cols × 8 rows)
    //
    // Row 1: ESC  TAB  Del  ↑  Backspace
    // Row 2: ESC  Scroll  ←  ↓  →
    // Row 3: Print  Pause  Home  End  =
    // Row 4: PgUp  NumLk  /  *  -
    // Row 5: PgDn  7  8  9  ┐
    // Row 6: Ins   4  5  6   +  (2-tall)
    // Row 7: Backspace  1  2  3  ┐
    // Row 8: 00  0(2w)  .         Enter (2-tall)

    @ViewBuilder
    private func portraitLayout(geo: GeometryProxy) -> some View {
        let cw = (geo.size.width  - 2*pad - 4*sp) / 5
        let rh = (geo.size.height - 2*pad - 7*sp) / 8

        VStack(spacing: sp) {
            // Rows 1–2 (ESC spans both rows in col 1)
            HStack(alignment: .top, spacing: sp) {
                k("Escape", "ESC", w: cw, h: rh*2+sp)
                VStack(spacing: sp) {
                    HStack(spacing: sp) {
                        k("Tab",       "TAB",    w: cw, h: rh)
                        k("Delete",    "Del",    w: cw, h: rh)
                        k("Up",        "↑",      w: cw, h: rh)
                        k("Backspace", "⌫ Bksp", w: cw, h: rh)
                    }
                    HStack(spacing: sp) {
                        k("ScrollLock", "Scroll", w: cw, h: rh)
                        k("Left",       "←",      w: cw, h: rh)
                        k("Down",       "↓",      w: cw, h: rh)
                        k("Right",      "→",      w: cw, h: rh)
                    }
                }
            }
            // Row 3
            HStack(spacing: sp) {
                k("PrintScreen",  "Print", w: cw, h: rh)
                k("Pause",        "Pause", w: cw, h: rh)
                k("Home",         "Home",  w: cw, h: rh)
                k("End",          "End",   w: cw, h: rh)
                k("NumpadEquals", "=",     w: cw, h: rh)
            }
            // Row 4
            HStack(spacing: sp) {
                k("PgUp",           "PgUp",  w: cw, h: rh)
                k("NumLock",        "NumLk", w: cw, h: rh)
                k("NumpadSlash",    "/",     w: cw, h: rh)
                k("NumpadAsterisk", "*",     w: cw, h: rh)
                k("NumpadMinus",    "-",     w: cw, h: rh)
            }

            // Rows 5–6 with + spanning vertically in col 5
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    // Row 5 (cols 1–4)
                    HStack(spacing: sp) {
                        k("PgDn",    "PgDn", w: cw, h: rh)
                        k("Numpad7", "7",    w: cw, h: rh)
                        k("Numpad8", "8",    w: cw, h: rh)
                        k("Numpad9", "9",    w: cw, h: rh)
                    }
                    // Row 6 (cols 1–4)
                    HStack(spacing: sp) {
                        k("Insert",  "Ins", w: cw, h: rh)
                        k("Numpad4", "4",   w: cw, h: rh)
                        k("Numpad5", "5",   w: cw, h: rh)
                        k("Numpad6", "6",   w: cw, h: rh)
                    }
                }
                // Col 5: + (rows 5–6)
                k("NumpadPlus", "+", w: cw, h: rh*2+sp)
            }

            // Rows 7–8 with Enter spanning vertically in col 5
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    // Row 7 (cols 1–4)
                    HStack(spacing: sp) {
                        k("Backspace", "⌫",  w: cw, h: rh)
                        k("Numpad1",   "1",  w: cw, h: rh)
                        k("Numpad2",   "2",  w: cw, h: rh)
                        k("Numpad3",   "3",  w: cw, h: rh)
                    }
                    // Row 8 (cols 1–4): 00 | 0(2w) | .
                    HStack(spacing: sp) {
                        doubleZero(w: cw,      h: rh)
                        k("Numpad0",   "0", w: cw*2+sp, h: rh)
                        k("NumpadDot", ".", w: cw,      h: rh)
                    }
                }
                // Col 5: Enter (rows 7–8)
                k("NumpadEnter", "Enter", w: cw, h: rh*2+sp)
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
                .background(isPressed ? Color.blue.opacity(0.7) : Color(UIColor.tertiarySystemBackground))
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
                .background(isPressed ? Color.blue.opacity(0.7) : Color(UIColor.tertiarySystemBackground))
                .cornerRadius(6)
        }
    }
}

struct NumPadView_Previews: PreviewProvider {
    static var previews: some View {
        let orientationManager = OrientationManager()
        return NumPadView(
            keyboardManager: KeyboardManager(bleManager: BLEManager()),
            orientationManager: orientationManager
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
