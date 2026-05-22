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

    // MARK: - Landscape (8 cols × 5 rows, matching Android)
    //
    // Row 0: ESC  TAB  Backspace(2 cols)  NumLk  /  *  -
    // Row 1: PrtSc  Ins  Pause  PgUp  7  8  9  [+] (spans rows 1-2)
    // Row 2: ScrLk  Home  End  PgDn  4  5  6
    // Row 3: DEL  UP(icon)  BKSP  00  1  2  3  [Enter] (spans rows 3-4)
    // Row 4: LEFT(icon)  DOWN(icon)  RIGHT(icon)  =  0(2 cols)  .

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        let cw = (geo.size.width - 2 * pad - 7 * sp) / 8
        let rh = (geo.size.height - 2 * pad - 4 * sp) / 5

        VStack(alignment: .leading, spacing: sp) {
            // Row 0
            HStack(spacing: sp) {
                k("Escape",         "ESC",    w: cw,      h: rh)
                k("Tab",            "TAB",    w: cw,      h: rh)
                k("Backspace",      "Bksp",   w: cw * 2 + sp, h: rh)
                k("NumLock",        "NumLk",  w: cw,      h: rh)
                k("NumpadSlash",    "/",      w: cw,      h: rh)
                k("NumpadAsterisk", "*",      w: cw,      h: rh)
                k("NumpadMinus",    "-",      w: cw,      h: rh)
            }

            // Rows 1–2 with + spanning vertically in col 8
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    // Row 1 (cols 1–7)
                    HStack(spacing: sp) {
                        k("PrintScreen", "PrtSc",  w: cw, h: rh)
                        k("Insert",      "Ins",    w: cw, h: rh)
                        k("Pause",       "Pause",  w: cw, h: rh)
                        k("PgUp",        "PgUp",   w: cw, h: rh)
                        k("Numpad7",     "7",      w: cw, h: rh)
                        k("Numpad8",     "8",      w: cw, h: rh)
                        k("Numpad9",     "9",      w: cw, h: rh)
                    }
                    // Row 2 (cols 1–7)
                    HStack(spacing: sp) {
                        k("ScrollLock", "ScrLk",  w: cw, h: rh)
                        k("Home",       "Home",   w: cw, h: rh)
                        k("End",        "End",    w: cw, h: rh)
                        k("PgDn",       "PgDn",   w: cw, h: rh)
                        k("Numpad4",    "4",      w: cw, h: rh)
                        k("Numpad5",    "5",      w: cw, h: rh)
                        k("Numpad6",    "6",      w: cw, h: rh)
                    }
                }
                // Col 8: + (rows 1–2)
                k("NumpadPlus", "+", w: cw, h: rh * 2 + sp)
            }

            // Rows 3–4 with Enter spanning vertically in col 8
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    // Row 3 (cols 1–7): DEL  UP(icon)  BKSP  00  1  2  3
                    HStack(spacing: sp) {
                        k("Delete",     "DEL",  w: cw, h: rh)
                        arrowIcon("Up", icon: "arrow.up", w: cw, h: rh)
                        k("Backspace",  "Bksp", w: cw, h: rh)
                        doubleZero(w: cw, h: rh)
                        k("Numpad1",    "1",    w: cw, h: rh)
                        k("Numpad2",    "2",    w: cw, h: rh)
                        k("Numpad3",    "3",    w: cw, h: rh)
                    }
                    // Row 4 (cols 1–7): LEFT(icon)  DOWN(icon)  RIGHT(icon)  =  0(2w)  .
                    HStack(spacing: sp) {
                        arrowIcon("Left",  icon: "arrow.left",  w: cw, h: rh)
                        arrowIcon("Down",  icon: "arrow.down",  w: cw, h: rh)
                        arrowIcon("Right", icon: "arrow.right", w: cw, h: rh)
                        k("NumpadEquals", "=",     w: cw,      h: rh)
                        numpadZero(w: cw * 2 + sp, h: rh)
                        k("NumpadDot",    ".",     w: cw,      h: rh)
                    }
                }
                // Col 8: Enter (rows 3–4)
                k("NumpadEnter", "Enter", w: cw, h: rh * 2 + sp)
            }
        }
        .padding(pad)
    }

    // MARK: - Portrait (5 cols × 8 rows, matching Android)
    //
    // Row 0-1: ESC(span 2 rows) | TAB        | DEL        | UP icon    | BKSP       |
    // Row 1:                    | ScrLk      | LEFT icon  | DOWN icon  | RIGHT icon |
    // Row 2:  PrtSc  | Pause  | Home  | End  | =
    // Row 3:  PgUp   | NumLk  | /     | *    | -
    // Row 4-5: PgDn  | 7      | 8     | 9    | + (span 2 rows)
    // Row 5:  Ins    | 4      | 5     | 6    |
    // Row 6-7: DEL   | 1      | 2     | 3    | Enter (span 2 rows)
    // Row 7:  00     | 0(span 2 cols) | .   |

    @ViewBuilder
    private func portraitLayout(geo: GeometryProxy) -> some View {
        let cw = (geo.size.width  - 2 * pad - 4 * sp) / 5
        let rh = (geo.size.height - 2 * pad - 7 * sp) / 8

        VStack(spacing: sp) {
            // Rows 0–1 (ESC spans both rows in col 1)
            HStack(alignment: .top, spacing: sp) {
                k("Escape", "ESC", w: cw, h: rh * 2 + sp)
                VStack(spacing: sp) {
                    HStack(spacing: sp) {
                        k("Tab",       "TAB",    w: cw, h: rh)
                        k("Delete",    "DEL",    w: cw, h: rh)
                        arrowIcon("Up", icon: "arrow.up", w: cw, h: rh)
                        k("Backspace", "Bksp",   w: cw, h: rh)
                    }
                    HStack(spacing: sp) {
                        k("ScrollLock", "ScrLk",  w: cw, h: rh)
                        arrowIcon("Left",  icon: "arrow.left",  w: cw, h: rh)
                        arrowIcon("Down",  icon: "arrow.down",  w: cw, h: rh)
                        arrowIcon("Right", icon: "arrow.right", w: cw, h: rh)
                    }
                }
            }
            // Row 2
            HStack(spacing: sp) {
                k("PrintScreen",  "PrtSc", w: cw, h: rh)
                k("Pause",        "Pause", w: cw, h: rh)
                k("Home",         "Home",  w: cw, h: rh)
                k("End",          "End",   w: cw, h: rh)
                k("NumpadEquals", "=",     w: cw, h: rh)
            }
            // Row 3
            HStack(spacing: sp) {
                k("PgUp",           "PgUp",  w: cw, h: rh)
                k("NumLock",        "NumLk", w: cw, h: rh)
                k("NumpadSlash",    "/",     w: cw, h: rh)
                k("NumpadAsterisk", "*",     w: cw, h: rh)
                k("NumpadMinus",    "-",     w: cw, h: rh)
            }

            // Rows 4–5 with + spanning vertically in col 5
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    // Row 4 (cols 1–4)
                    HStack(spacing: sp) {
                        k("PgDn",    "PgDn", w: cw, h: rh)
                        k("Numpad7", "7",    w: cw, h: rh)
                        k("Numpad8", "8",    w: cw, h: rh)
                        k("Numpad9", "9",    w: cw, h: rh)
                    }
                    // Row 5 (cols 1–4)
                    HStack(spacing: sp) {
                        k("Insert",  "Ins", w: cw, h: rh)
                        k("Numpad4", "4",   w: cw, h: rh)
                        k("Numpad5", "5",   w: cw, h: rh)
                        k("Numpad6", "6",   w: cw, h: rh)
                    }
                }
                // Col 5: + (rows 4–5)
                k("NumpadPlus", "+", w: cw, h: rh * 2 + sp)
            }

            // Rows 6–7 with Enter spanning vertically in col 5
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    // Row 6 (cols 1–4): DEL  1  2  3
                    HStack(spacing: sp) {
                        k("Delete",    "DEL", w: cw, h: rh)
                        k("Numpad1",   "1",   w: cw, h: rh)
                        k("Numpad2",   "2",   w: cw, h: rh)
                        k("Numpad3",   "3",   w: cw, h: rh)
                    }
                    // Row 7 (cols 1–4): 00  0(2w)  .
                    HStack(spacing: sp) {
                        doubleZero(w: cw,      h: rh)
                        numpadZero(w: cw * 2 + sp, h: rh)
                        k("NumpadDot", ".",     w: cw, h: rh)
                    }
                }
                // Col 5: Enter (rows 6–7)
                k("NumpadEnter", "Enter", w: cw, h: rh * 2 + sp)
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
                .cornerRadius(8)
        }
    }

    /// Arrow icon key — uses SF Symbols to match Android's drawable icon cells.
    @ViewBuilder
    private func arrowIcon(_ key: String, icon: String, w: CGFloat, h: CGFloat) -> some View {
        KeyPressButton(
            onPress: {
                HapticFeedbackManager.shared.triggerButtonPress()
                keyboardManager.handleKeyDown(key)
            },
            onRelease: { keyboardManager.handleKeyUp(key) }
        ) { isPressed in
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: w * 0.45, height: h * 0.45)
                .foregroundColor(isPressed ? .white : .primary)
                .frame(width: w, height: h)
                .background(isPressed ? Color.blue.opacity(0.7) : Color(UIColor.tertiarySystemBackground))
                .cornerRadius(8)
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
                .cornerRadius(8)
        }
    }

    /// Numpad 0 key — shows "0" label (Android shows Openterface wordmark icon).
    @ViewBuilder
    private func numpadZero(w: CGFloat, h: CGFloat) -> some View {
        let fontSize = min(min(w, h) * 0.38, 16)
        KeyPressButton(
            onPress: {
                HapticFeedbackManager.shared.triggerButtonPress()
                keyboardManager.handleKeyDown("Numpad0")
            },
            onRelease: { keyboardManager.handleKeyUp("Numpad0") }
        ) { isPressed in
            Image("openterface_wordmark")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: w * 0.75, height: h * 0.75)
                .frame(width: w, height: h)
                .background(isPressed ? Color.blue.opacity(0.7) : Color(UIColor.tertiarySystemBackground))
                .cornerRadius(8)
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
