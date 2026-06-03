//
//  LatchBadgeView.swift
//  KeyMod
//
//  Visual overlay for modules that are latched via hold-lock or turbo gesture.
//  Shows a centered icon (lock for hold, repeat for turbo) with a subtle background.
//  Matches Android's LATCH_BADGE sizing (32-56dp, 52% of module min-side).
//

import SwiftUI

struct LatchBadgeView: View {
    let state: LatchState

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.65))
            Image(systemName: state.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 24, height: 24)
    }
}
