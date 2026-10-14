import SwiftUI
import AppKit

/// Finder-tag-style mark filter: one circle per mark, each an on/off switch — filled = that
/// group's photos are shown, outline = hidden. The first (neutral) circle is "ohne Markierung".
/// The count under every circle is the number you want in the second culling pass.
struct FilterBar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

    private let size: CGFloat = 20
    private let slot: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 2) {
                toggleAllButton
                Divider().frame(height: size).padding(.horizontal, 6).padding(.top, 1)
                chip(bucket: 0)
                    .help("Ohne Markierung (\(app.unmarkedCount)) · ⌥-Klick: nur diese")
                ForEach(1...MarkDefinition.count, id: \.self) { mark in
                    chip(bucket: mark)
                        .help("\(settings.markName(mark)) · Taste \(mark) · \(app.markCounts[mark] ?? 0) Bilder · ⌥-Klick: nur diese")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var toggleAllButton: some View {
        let allShown = app.tagFilter.allShown
        return Button {
            app.tagFilter.setAll(shown: !allShown)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: allShown ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: size - 3, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(allShown ? Color.accentColor : Color.secondary)
                    .frame(width: size, height: size)
                Text("Alle")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: slot)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(allShown ? "Alle abwählen" : "Alle anwählen")
    }

    private func chip(bucket: Int) -> some View {
        let on = app.tagFilter.isShown(bucket)
        let count = bucket == 0 ? app.unmarkedCount : (app.markCounts[bucket] ?? 0)
        return Button {
            if NSEvent.modifierFlags.contains(.option) { app.tagFilter.solo(bucket) }
            else { app.tagFilter.toggle(bucket) }
        } label: {
            VStack(spacing: 3) {
                Group {
                    if bucket == 0 {
                        UnmarkedBadge(size: size, on: on)
                    } else {
                        MarkBadge(mark: bucket, size: size, style: on ? .filled : .outline)
                    }
                }
                .opacity(on ? 1 : 0.7)
                Text(count > 0 ? "\(count)" : "·")
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(on && count > 0 ? Color.secondary : Color.secondary.opacity(0.45))
            }
            .frame(width: slot)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: on)
    }
}
