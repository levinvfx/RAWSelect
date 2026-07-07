import SwiftUI

/// Always-visible tag filter bar. Every bucket is shown by default; clicking a
/// chip hides that bucket (chip greys out). "Alle" = photos without a mark,
/// followed by colour marks 1–9.
struct FilterBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(bucket: 0, title: "Alle", dot: nil, count: app.unmarkedCount)
                    .help("Bilder ohne Markierung")

                divider

                ForEach(1...9, id: \.self) { mark in
                    chip(bucket: mark, title: "\(mark)", dot: MarkStyle.color(for: mark),
                         count: app.markCounts[mark] ?? 0)
                        .help("Markierung \(mark)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .background(.bar)
    }

    private var divider: some View {
        Divider().frame(height: 20).padding(.horizontal, 2)
    }

    private func chip(bucket: Int, title: String, dot: Color?, count: Int) -> some View {
        let shown = app.tagFilter.isShown(bucket)
        return Button {
            app.tagFilter.toggle(bucket)
        } label: {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(shown ? dot : Color.secondary.opacity(0.4))
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: shown ? "circle.grid.2x2.fill" : "circle.grid.2x2")
                        .font(.caption)
                        .foregroundStyle(shown ? Color.primary : Color.secondary)
                }
                Text(title)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(shown ? Color.primary : Color.secondary)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(
                Capsule().fill(shown
                    ? Color(nsColor: .quaternaryLabelColor).opacity(0.55)
                    : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(Color(nsColor: .separatorColor),
                                       lineWidth: shown ? 0 : 1)
            )
            .opacity(shown ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
