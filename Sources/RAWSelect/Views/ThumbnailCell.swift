import SwiftUI

/// A single thumbnail in the grid or filmstrip. Loads its image lazily via the
/// shared ThumbnailLoader and shows the file name + mark/type badges.
struct ThumbnailCell: View {
    @EnvironmentObject var settings: AppSettings
    let group: PhotoGroup
    let isSelected: Bool
    var isCurrent: Bool = false
    var side: CGFloat = 150
    var showsCaption: Bool = true

    @State private var image: NSImage?
    @State private var isSharp = false

    /// The photo under the cursor is what 1–7 hit — it keeps its frame even when nothing is selected.
    private var borderColor: Color { isSelected || isCurrent ? .accentColor : .clear }

    private var sharpPx: Int { Int(side * PreviewConfig.gridSharpFactor) }

    /// Whatever the cache holds right now, read synchronously: a cell that is rebuilt (back from
    /// the loupe, scrolling, filter change) shows its picture in the very first frame instead of
    /// one empty frame, then a soft one — the grid used to blink on every Esc.
    private var shownImage: NSImage? {
        if let image { return image }
        let loader = ThumbnailLoader.shared
        return loader.cached(for: group.previewURL, maxPixel: sharpPx)
            ?? loader.cached(for: group.previewURL, maxPixel: PreviewConfig.tinyMaxPixel)
    }

    private var typeText: String? { group.typeLabel }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))

                if let image = shownImage {
                    // Always show whatever we have (tiny fallback or sharp) – no
                    // spinner, so fast scrolling never flashes a loading state.
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(isSharp ? .medium : .low)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if group.mark != 0 { markBadge }
                if let typeText { typeBadge(typeText) }
            }
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: isCurrent ? 4 : (isSelected ? 3 : 0))
            )

            if showsCaption {
                Text(group.displayName)
                    .font(.caption)
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(maxWidth: side)
            }
        }
        // The size is part of the id: after changing the tile size the sharp tier is re-fetched.
        .task(id: "\(group.id)|\(sharpPx)") {
            let loader = ThumbnailLoader.shared
            let sharpPx = self.sharpPx
            if let ready = loader.cached(for: group.previewURL, maxPixel: sharpPx), sharpPx > PreviewConfig.tinyMaxPixel {
                image = ready; isSharp = true; return
            }
            if let tiny = await loader.thumbnail(for: group.previewURL, maxPixel: PreviewConfig.tinyMaxPixel) {
                if !isSharp { image = tiny }
            }
            // Only decode a dedicated sharp size when it is actually LARGER than the tiny
            // fallback. In the filmstrip the cells are small enough that the "sharp" target
            // falls below the tiny size — decoding it was pure waste and even downgraded the
            // picture (a smaller image replacing the bigger tiny one).
            guard sharpPx > PreviewConfig.tinyMaxPixel else { isSharp = true; return }
            if let sharp = await loader.thumbnail(for: group.previewURL, maxPixel: sharpPx) {
                image = sharp
                isSharp = true
            }
        }
    }


    /// Dot size follows the cell: 11 pt in the filmstrip, ~14 pt at the default grid size, 18 pt on
    /// big tiles — the same proportion everywhere, like Finder tag dots on icons.
    private var badgeSize: CGFloat { min(18, max(11, (side * 0.095).rounded())) }

    private var markBadge: some View {
        VStack {
            HStack {
                Spacer()
                MarkBadge(mark: group.mark, size: badgeSize, ring: true)
                    .padding(badgeSize * 0.45)
            }
            Spacer()
        }
    }

    private func typeBadge(_ text: String) -> some View {
        VStack {
            Spacer()
            HStack {
                Text(text)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(6)
                Spacer()
            }
        }
    }
}
