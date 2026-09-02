import SwiftUI
import AppKit

/// Compact Photo-Mechanic-style colour-swatch filter. Each swatch is an on/off
/// switch: on = that group's photos are shown, off (dimmed) = hidden. The first
/// (checkered) swatch is "Alle" = photos without any mark. All on by default.
struct FilterBar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

    private let size: CGFloat = 22

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 4) {
                toggleAllButton
                Divider().frame(height: size)
                swatch(bucket: 0, color: nil)
                    .help("Ohne Markierung (\(app.unmarkedCount)) · ⌥-Klick: nur diese")
                ForEach(1...9, id: \.self) { mark in
                    swatch(bucket: mark, color: settings.markColor(mark))
                        .help("\(settings.markName(mark)) (\(app.markCounts[mark] ?? 0)) · ⌥-Klick: nur diese")
                }
            }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var toggleAllButton: some View {
        let allShown = app.tagFilter.allShown
        return Button {
            app.tagFilter.setAll(shown: !allShown)
        } label: {
            Image(systemName: allShown ? "checkmark.square.fill" : "square")
                .font(.system(size: 15))
                .foregroundStyle(allShown ? Color.accentColor : .secondary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(allShown ? "Alle abwählen" : "Alle anwählen")
    }

    private func swatch(bucket: Int, color: Color?) -> some View {
        let on = app.tagFilter.isShown(bucket)
        let count = bucket == 0 ? app.unmarkedCount : (app.markCounts[bucket] ?? 0)
        return Button {
            if NSEvent.modifierFlags.contains(.option) { app.tagFilter.solo(bucket) }
            else { app.tagFilter.toggle(bucket) }
        } label: {
          VStack(spacing: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(fill(color: color, on: on))
                if color == nil {
                    Checkerboard().opacity(on ? 0.9 : 0.25)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("\(bucket)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(on ? .white : color!.opacity(0.85))
                        .shadow(color: .black.opacity(on ? 0.35 : 0), radius: 1)
                }
            }
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(borderColor(color: color, on: on), lineWidth: on ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4))
            // The count lives right under the swatch: "how many on 1?" used to need a hover
            // over nine tooltips — in the second culling pass that is the one number you want.
            Text(count > 0 ? "\(count)" : " ")
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .foregroundStyle(on ? Color.secondary : Color.secondary.opacity(0.5))
                .frame(width: size)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fill(color: Color?, on: Bool) -> Color {
        if !on { return Color.black.opacity(0.32) }        // off = dark/empty
        return color ?? Color(nsColor: .windowBackgroundColor)
    }

    private func borderColor(color: Color?, on: Bool) -> Color {
        if on { return .white.opacity(0.7) }
        return (color ?? .secondary).opacity(0.7)          // keep it identifiable when off
    }
}

/// Small checkerboard used for the "no mark" swatch.
private struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let n = 4
            let s = size.width / CGFloat(n)
            for r in 0..<n {
                for c in 0..<n where (r + c) % 2 == 0 {
                    let rect = CGRect(x: CGFloat(c) * s, y: CGFloat(r) * s, width: s, height: s)
                    ctx.fill(Path(rect), with: .color(.gray.opacity(0.7)))
                }
            }
        }
        .background(Color.white.opacity(0.85))
    }
}
