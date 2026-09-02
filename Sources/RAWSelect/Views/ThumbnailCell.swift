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

    private var borderColor: Color { isSelected ? .accentColor : .clear }

    private var typeText: String? {
        let raw = group.files.contains { PhotoTypes.isRaw($0) }
        let jpg = group.files.contains { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
        if raw && jpg { return "RAW+JPG" }
        if raw { return "RAW" }
        if jpg { return "JPG" }
        return group.previewURL.pathExtension.uppercased()
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))

                if let image {
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
        .task(id: group.id) {
            let loader = ThumbnailLoader.shared
            let sharpPx = Int(side * PreviewConfig.gridSharpFactor)
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


    private var markBadge: some View {
        VStack {
            HStack {
                Spacer()
                Text("\(group.mark)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(settings.markColor(group.mark)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
                    .padding(6)
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
