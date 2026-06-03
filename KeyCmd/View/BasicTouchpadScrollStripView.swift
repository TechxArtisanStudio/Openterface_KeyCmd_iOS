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
                Color(red: 44/255, green: 44/255, blue: 46/255)
                LinearGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.07), Color.clear]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.08), Color.clear]),
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                RadialGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.09), Color.clear]),
                    center: .init(x: 0.28, y: 0.24),
                    startRadius: 0,
                    endRadius: 160
                )
                RadialGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.11), Color.clear]),
                    center: .init(x: 0.78, y: 0.82),
                    startRadius: 0,
                    endRadius: 200
                )

                // Up/down chevron indicators
                VStack(spacing: 0) {
                    let chevronSize = min(24, max(14, geometry.size.width * 0.85))
                    Image(systemName: "chevron.up")
                        .font(.system(size: chevronSize, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.86))
                        .frame(width: chevronSize, height: chevronSize)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: chevronSize, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.86))
                        .frame(width: chevronSize, height: chevronSize)
                }
                .padding(.vertical, 6)
            }
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 3)
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
