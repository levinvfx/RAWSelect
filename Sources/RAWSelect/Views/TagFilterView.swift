import SwiftUI

/// Photo-Mechanic-style tag filter shown in a popover: tick which tags to show.
/// Nothing ticked = show all photos.
struct TagFilterView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Nach Tags anzeigen").font(.headline)
                Spacer()
                Button("Alle") { app.tagFilter.reset() }
                    .buttonStyle(.link)
                    .disabled(!app.tagFilter.isActive)
            }
            .padding(.bottom, 4)

            row(title: "Unmarkiert", icon: ("circle.dashed", .secondary),
                count: app.unmarkedCount, isOn: app.tagFilter.unmarked) {
                app.tagFilter.unmarked.toggle()
            }
            row(title: "Ausschuss", icon: ("xmark.circle.fill", .red),
                count: app.rejectCount, isOn: app.tagFilter.reject) {
                app.tagFilter.reject.toggle()
            }

            Divider().padding(.vertical, 4)

            ForEach(1...9, id: \.self) { mark in
                row(title: "Markierung \(mark)", dot: MarkStyle.color(for: mark),
                    count: app.markCounts[mark] ?? 0, isOn: app.tagFilter.marks.contains(mark)) {
                    if app.tagFilter.marks.contains(mark) { app.tagFilter.marks.remove(mark) }
                    else { app.tagFilter.marks.insert(mark) }
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func row(title: String, icon: (String, Color)? = nil, dot: Color? = nil,
                     count: Int, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                if let dot {
                    Circle().fill(dot).frame(width: 10, height: 10)
                } else if let icon {
                    Image(systemName: icon.0).foregroundStyle(icon.1).frame(width: 14)
                }
                Text(title)
                Spacer()
                if count > 0 {
                    Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
