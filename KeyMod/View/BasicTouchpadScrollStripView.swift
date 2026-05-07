//
//  BasicTouchpadScrollStripView.swift
//  KeyMod
//
//  Vertical scroll strip on the right edge of the touchpad in Basic mode.
//  Matches Android's BasicPortraitScrollStripView.

import SwiftUI

struct BasicTouchpadScrollStripView: View {
    let mouseManager: MouseManager

    @State private var lastScrollY: CGFloat?
    @State private var isScrolling: Bool = false

    /// Pixels per wheel unit (matches Android STRIP_PIXELS_PER_WHEEL_UNIT = 5f)
    private let pixelsPerWheelUnit: CGFloat = 5.0

    var body: some View {
        GeometryReader { geometry in
            Color(UIColor.secondarySystemBackground)
                .overlay(
                    VStack {
                        Text("scroll")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.5))
                            .rotationEffect(.degrees(-90))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                )
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
                                let wheelUnits = Int(deltaY / pixelsPerWheelUnit)
                                if wheelUnits != 0 {
                                    mouseManager.handleScroll(deltaX: 0, deltaY: -wheelUnits)
                                    lastScrollY = value.location.y
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
