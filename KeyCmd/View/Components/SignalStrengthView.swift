import SwiftUI

// ponytail: 4-bar signal icon, bars filled based on RSSI quality
struct SignalStrengthView: View {
    let rssi: NSNumber?

    private var barCount: Int {
        guard let rssi = rssi else { return 0 }
        let value = rssi.intValue
        // ponytail: coarse buckets, -50=excellent, -90=dead
        if value >= -60 { return 4 }
        if value >= -70 { return 3 }
        if value >= -80 { return 2 }
        return 1
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                Rectangle()
                    .fill(bar <= barCount ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 3, height: CGFloat(bar) * 3 + 2)
            }
        }
        .frame(height: 16)
    }
}

#Preview {
    VStack(spacing: 20) {
        SignalStrengthView(rssi: -45)
        SignalStrengthView(rssi: -65)
        SignalStrengthView(rssi: -75)
        SignalStrengthView(rssi: -85)
        SignalStrengthView(rssi: nil)
    }
}
