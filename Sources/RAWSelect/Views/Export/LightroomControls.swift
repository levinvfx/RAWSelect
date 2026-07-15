import SwiftUI

/// Lightroom-CC-style slider: thin track, round knob, label left, value right,
/// reset arrow (or double-click). Optional gradient track for white balance / HSL.
/// Bipolar sliders fill from the neutral point toward the knob, like Lightroom.
struct LRSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -100...100
    var neutral: Double = 0
    var format: (Double) -> String = { String(format: "%+.0f", $0) }
    var gradient: [Color]? = nil
    var onEdit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.82))
                .frame(width: 88, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in track(geo.size.width, geo.size.height) }
                .frame(height: 18)
            Text(format(value))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Button { value = neutral; onEdit() } label: {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(abs(value - neutral) > 0.0001 ? 1 : 0.2)
            .frame(width: 14)
        }
        .frame(height: 22)
    }

    private func frac(_ v: Double) -> CGFloat {
        CGFloat((v - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    @ViewBuilder private func track(_ w: CGFloat, _ h: CGFloat) -> some View {
        let midY = h / 2
        let knobX = min(max(frac(value) * w, 0), w)
        let neutralX = frac(neutral) * w
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.14))
                .frame(width: w, height: 3).position(x: w / 2, y: midY)
            if let g = gradient {
                Capsule().fill(LinearGradient(colors: g, startPoint: .leading, endPoint: .trailing))
                    .frame(width: w, height: 3).position(x: w / 2, y: midY)
            } else {
                let lo = min(knobX, neutralX), hi = max(knobX, neutralX)
                Capsule().fill(Color.white.opacity(0.5))
                    .frame(width: max(0, hi - lo), height: 3).position(x: (lo + hi) / 2, y: midY)
            }
            Circle().fill(.white)
                .frame(width: 13, height: 13)
                .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
                .position(x: knobX, y: midY)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            let f = min(max(g.location.x / w, 0), 1)
            value = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
            onEdit()
        })
        .onTapGesture(count: 2) { value = neutral; onEdit() }
    }
}

/// Collapsible Lightroom-style panel section with an uppercase header.
struct LRSection<Content: View>: View {
    let title: String
    @State private var open = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold)).kerning(0.6)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { VStack(spacing: 5) { content() } }
        }
        .padding(.top, 3)
    }
}
