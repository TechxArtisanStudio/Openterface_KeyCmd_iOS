import SwiftUI

struct NumpadGridView: View {
    let keys: [[NumpadKeyData]]
    @ObservedObject var keyboardManager: KeyboardManager

    var body: some View {
        GeometryReader { geometry in
            let rows = CGFloat(keys.count)
            let cols = CGFloat(keys.map(\.count).max() ?? 4)
            let availableWidth = geometry.size.width - 16
            let availableHeight = geometry.size.height - 16
            let keyWidth = (availableWidth - (cols - 1) * 4) / cols
            let keyHeight = (availableHeight - (rows - 1) * 4) / rows

            VStack(spacing: 4) {
                ForEach(0..<keys.count, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<keys[row].count, id: \.self) { col in
                            NumpadButton(
                                key: keys[row][col],
                                keyboardManager: keyboardManager,
                                width: keyWidth,
                                height: keyHeight
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
    }
}

private struct NumpadButton: View {
    let key: NumpadKeyData
    let keyboardManager: KeyboardManager
    let width: CGFloat
    let height: CGFloat
    @State private var isPressed = false

    private var buttonColor: Color {
        numpadColorFromHex(key.colorHex).opacity(0.8)
    }

    var body: some View {
        Button {
            isPressed = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                keyboardManager.handleKeyPress(key.keyCode)
            }
        } label: {
            VStack(spacing: 2) {
                Text(key.display)
                    .font(.system(size: min(width, height) * 0.25, weight: .bold))
                    .foregroundColor(.white)

                Text(key.description)
                    .font(.system(size: min(width, height) * 0.12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(buttonColor)
                    .shadow(color: .black.opacity(0.2), radius: isPressed ? 1 : 3, x: 0, y: isPressed ? 1 : 2)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private func numpadColorFromHex(_ hex: String) -> Color {
    var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    sanitized = sanitized.replacingOccurrences(of: "#", with: "")
    var rgb: UInt64 = 0
    Scanner(string: sanitized).scanHexInt64(&rgb)
    let r = Double((rgb & 0xFF0000) >> 16) / 255.0
    let g = Double((rgb & 0x00FF00) >> 8) / 255.0
    let b = Double(rgb & 0x0000FF) / 255.0
    return Color(red: r, green: g, blue: b)
}
