import SwiftUI

/// THE one way a colour mark (1–9) is drawn anywhere in the app: a Finder-tag-like circle in
/// the mark's colour with its number inside. Grid badge, filmstrip, filter chips, loupe pill,
/// compare header and the settings editor all use this view, so form, type and colour logic
/// can never drift apart again.
///
/// - `size`: circle diameter in points; the digit scales with it.
/// - `style`: `.filled` (the mark is set / the filter is on) or `.outline` (filter off: only a
///   ring and the digit in the mark's colour — identifiable, but clearly not active).
/// - `ring`: a thin light ring for badges that sit ON a photo, so a dark mark stays visible on
///   a dark picture (and a light one on snow). Off by default for chips on plain surfaces.
struct MarkBadge: View {
    enum Style { case filled, outline }

    let mark: Int
    var size: CGFloat = 20
    var style: Style = .filled
    var ring = false

    @EnvironmentObject private var settings: AppSettings

    private var color: Color { settings.markColor(mark) }
    private var digit: Font { .system(size: (size * 0.56).rounded(), weight: .semibold, design: .rounded) }

    var body: some View {
        ZStack {
            switch style {
            case .filled:
                Circle().fill(color)
                Text("\(mark)")
                    .font(digit).monospacedDigit()
                    .foregroundStyle(settings.markTextColor(mark))
            case .outline:
                Circle().strokeBorder(color, lineWidth: max(1.5, size * 0.08))
                Text("\(mark)")
                    .font(digit).monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if ring { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
        }
        .shadow(color: ring ? .black.opacity(0.25) : .clear, radius: 1.5, y: 0.5)
        .accessibilityLabel("Markierung \(mark), \(settings.markName(mark))")
    }
}

/// The "no mark" chip of the filter bar — the same circle, but neutral: a hairline ring with a
/// small dot, like an empty tag slot in the Finder.
struct UnmarkedBadge: View {
    var size: CGFloat = 20
    var on = true

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.secondary.opacity(on ? 0.9 : 0.45), lineWidth: max(1.5, size * 0.08))
            Circle().fill(Color.secondary.opacity(on ? 0.55 : 0.25)).frame(width: size * 0.28, height: size * 0.28)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Ohne Markierung")
    }
}
