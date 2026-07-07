import SwiftUI

/// A single thumbnail in the grid or filmstrip. Loads its image lazily via the
/// shared ThumbnailLoader and shows the file name + mark badge.
struct ThumbnailCell: View {
    let group: PhotoGroup
    let isSelected: Bool
    var isCurrent: Bool = false
    var side: CGFloat = 150
    var showsCaption: Bool = true

    @State private var image: NSImage?

    private var borderColor: Color {
        if isSelected { return .accentColor }
        return .clear
    }

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
                        .opacity(group.reject ? 0.45 : 1)
                } else {
                    ProgressView().controlSize(.small)
                }

                if group.mark != 0 {
                    markBadge
                }
                if group.reject {
                    rejectBadge
                }
                if group.rating > 0 {
                    starsOverlay
                }
                if group.isRaw {
                    rawBadge
                }
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

    private var rejectBadge: some View {
        VStack {
            HStack {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.red))
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
                    .padding(6)
                Spacer()
            }
            Spacer()
        }
    }

    private var starsOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= group.rating ? "star.fill" : "star")
                        .font(.system(size: max(7, side * 0.06)))
                        .foregroundStyle(i <= group.rating ? .yellow : .white.opacity(0.5))
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.45)))
            .padding(.bottom, 6)
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
