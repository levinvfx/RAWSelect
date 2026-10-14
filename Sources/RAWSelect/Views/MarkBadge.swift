import SwiftUI

/// THE one way a colour mark is drawn anywhere in the app: a Finder-tag dot. Since 2.0 there is no
/// digit inside — like Finder tags, a mark is recognised by its colour (the keys 1–7 stay). Grid
/// badge, filmstrip, filter bar, loupe pill, compare header and the settings editor all use this
/// view, so form and colour can never drift apart again.
///
/// - `size`: dot diameter in points.
/// - `style`: `.filled` (mark set / filter on) or `.outline` (filter off: a ring in the mark's
///   colour — identifiable, but clearly not active).
/// - `ring`: a white ring + soft shadow for dots that sit ON a photo, so a dark mark stays visible
///   on a dark picture and a light one on snow — the way Finder draws tags over icons.
struct MarkBadge: View {
    enum Style { case filled, outline }

    let mark: Int
    var size: CGFloat = 14
    var style: Style = .filled
    var ring = false

    @EnvironmentObject private var settings: AppSettings

    private var color: Color { settings.markColor(mark) }

    var body: some View {
        ZStack {
            switch style {
            case .filled:
                Circle().fill(color)
                // The hairline a shade darker than the fill, as on Finder tags: gives light colours
                // (yellow, grey) an edge on light backgrounds without looking outlined.
                Circle().strokeBorder(Color.black.opacity(0.14), lineWidth: max(1, size * 0.07))
            case .outline:
                Circle().strokeBorder(color, lineWidth: max(1.5, size * 0.11))
            }
        }
        .frame(width: size, height: size)
        .padding(ring ? max(1.5, size * 0.12) : 0)
        .background {
            if ring { Circle().fill(.white) }
        }
        .shadow(color: ring ? .black.opacity(0.3) : .clear, radius: 1.5, y: 0.5)
        .accessibilityLabel("Markierung \(settings.markName(mark))")
    }
}

/// The "no mark" chip of the filter bar — the same dot, but neutral: a hairline ring with a small
/// centre, like an empty tag slot.
struct UnmarkedBadge: View {
    var size: CGFloat = 14
    var on = true

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.secondary.opacity(on ? 0.9 : 0.45), lineWidth: max(1.5, size * 0.09))
            Circle().fill(Color.secondary.opacity(on ? 0.55 : 0.25)).frame(width: size * 0.3, height: size * 0.3)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Ohne Markierung")
    }
}
