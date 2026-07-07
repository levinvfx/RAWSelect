import SwiftUI

/// Always-visible, Photo-Mechanic-style tag filter bar above the grid. Click a
/// chip to toggle whether that tag is shown. Nothing active = all photos.
struct FilterBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Alle", systemImage: "square.grid.2x2",
                     active: !app.tagFilter.isActive, tint: .accentColor) {
                    app.tagFilter.reset()
                }

                divider

                chip(title: "Unmarkiert", systemImage: "circle.dashed",
                     count: app.unmarkedCount, active: app.tagFilter.unmarked, tint: .secondary) {
                    app.tagFilter.unmarked.toggle()
                }
                chip(title: "Ausschuss", systemImage: "xmark.circle.fill",
                     count: app.rejectCount, active: app.tagFilter.reject, tint: .red) {
                    app.tagFilter.reject.toggle()
                }

                divider

                ForEach(1...9, id: \.self) { mark in
                    chip(number: mark, dot: MarkStyle.color(for: mark),
                         count: app.markCounts[mark] ?? 0,
                         active: app.tagFilter.marks.contains(mark)) {
                        if app.tagFilter.marks.contains(mark) { app.tagFilter.marks.remove(mark) }
                        else { app.tagFilter.marks.insert(mark) }
                    }
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

    // Text/icon chip (Alle, Unmarkiert, Ausschuss).
    private func chip(title: String, systemImage: String, count: Int = -1,
                      active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(active ? tint : .secondary)
                Text(title)
                if count >= 0 { countBadge(count) }
            }
            .font(.callout)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(chipBackground(active: active))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // Compact numbered colour-mark chip.
    private func chip(number: Int, dot: Color, count: Int,
                      active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 11, height: 11)
                Text("\(number)").font(.callout.monospacedDigit())
                if count > 0 { countBadge(count) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(chipBackground(active: active, tint: dot))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func chipBackground(active: Bool, tint: Color = .accentColor) -> some View {
        Capsule()
            .fill(active ? tint.opacity(0.22) : Color(nsColor: .quaternaryLabelColor).opacity(0.4))
            .overlay(Capsule().strokeBorder(active ? tint.opacity(0.9) : .clear, lineWidth: 1))
    }
}
