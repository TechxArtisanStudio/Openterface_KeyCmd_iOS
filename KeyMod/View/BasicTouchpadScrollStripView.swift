//
//  BasicTouchpadScrollStripView.swift
//  KeyMod
//
//  Vertical scroll strip on the right edge of the touchpad in Basic mode.
//  Matches Android's BasicPortraitScrollStripView.

import SwiftUI

struct BasicTouchpadScrollStripView: View {
    let mouseManager: MouseManager
    var labelFontSize: CGFloat = 7

    @State private var lastScrollY: CGFloat?
    @State private var isScrolling: Bool = false

    /// Pixels per wheel unit (matches Android STRIP_PIXELS_PER_WHEEL_UNIT = 5f)
    private let pixelsPerWheelUnit: CGFloat = 5.0

    private var sensitivity: Double { KmBasicKeyboardPrefs.shared.stripScrollSensitivity }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(UIColor.secondarySystemBackground)

                // Up/down chevron indicators
                VStack(spacing: 0) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: labelFontSize + 2, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.4))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: labelFontSize + 2, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .padding(.vertical, 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if lastScrollY == nil {
                            lastScrollY = value.location.y
                            isScrolling = true
                        }

                        guard let prevY = lastScrollY else { return }
                        let deltaY = value.location.y - prevY

                        // Only send scroll after moving past threshold
                        if abs(deltaY) > pixelsPerWheelUnit {
                            let wheelUnits = Int(deltaY / pixelsPerWheelUnit * sensitivity)
                            if wheelUnits != 0 {
                                mouseManager.handleScroll(deltaX: 0, deltaY: -wheelUnits)
                                lastScrollY = value.location.y
                                HapticFeedbackManager.shared.triggerScrollTick()
                            }
                        }
                    }
                    .onEnded { _ in
                        lastScrollY = nil
                        isScrolling = false
                    }
            )
        }
        .clipped()
    }
}
