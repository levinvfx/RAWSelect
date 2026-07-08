import SwiftUI
import AppKit

// MARK: - 7. Über / Credits

/// Small "about" tab: brand logo (theme-aware), author, and contact links.
struct CreditsSettingsTab: View {
    @Environment(\.colorScheme) private var colorScheme

    private var logo: NSImage? { AppAssets.logo(dark: colorScheme == .dark) }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 4)

            if let logo {
                Image(nsImage: logo)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 72)
            } else {
                Text(AppInfo.brand).font(.system(size: 34, weight: .bold, design: .rounded))
            }

            VStack(spacing: 2) {
                Text(AppInfo.author).font(.title3.weight(.semibold))
                Text(AppInfo.brand).font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                LinkChip(title: "Instagram", systemImage: "camera", url: AppInfo.instagramURL)
                LinkChip(title: AppInfo.email, systemImage: "envelope", url: AppInfo.emailURL)
            }

            Spacer()

            Text("\(AppInfo.name) \(AppInfo.version)")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A pill-shaped external link button.
private struct LinkChip: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
        }
        .buttonStyle(.plain)
        .pointerStyleLink()
    }
}

private extension View {
    /// Hand cursor on hover (no-op fallback below macOS 15).
    @ViewBuilder func pointerStyleLink() -> some View {
        if #available(macOS 15.0, *) { self.pointerStyle(.link) } else { self }
    }
}
