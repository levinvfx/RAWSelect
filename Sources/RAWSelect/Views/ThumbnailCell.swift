import SwiftUI

/// A single thumbnail in the grid or filmstrip. Loads its image lazily via the
/// shared ThumbnailLoader and shows the file name + mark badge.
struct ThumbnailCell: View {
    let group: PhotoGroup
    let isSelected: Bool
    var side: CGFloat = 150
    var showsCaption: Bool = true

    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ProgressView().controlSize(.small)
                }

                if group.mark != 0 {
                    markBadge
                }
                if group.isRaw {
                    rawBadge
                }
            }
            .frame(width: side, height: side)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            if showsCaption {
                Text(group.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(maxWidth: side)
            }
        }
        .task(id: group.id) {
            let maxPixel = Int(side * 2.2)
            image = await ThumbnailLoader.shared.thumbnail(for: group.previewURL, maxPixel: maxPixel)
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
                    .background(Circle().fill(MarkStyle.color(for: group.mark)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
                    .padding(6)
            }
            Spacer()
        }
    }

    private var rawBadge: some View {
        VStack {
            Spacer()
            HStack {
                Text("RAW")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(6)
                Spacer()
            }
        }
    }
}
