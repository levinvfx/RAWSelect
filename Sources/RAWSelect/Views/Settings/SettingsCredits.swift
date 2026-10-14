import SwiftUI
import AppKit

// MARK: - 7. Über / Credits

/// About tab: VFX Media wordmark, two prominent links (Instagram, website) and the secondary ones
/// (feedback, mail, privacy) as quiet text links underneath — one clear hierarchy instead of five
/// equally loud pills.
struct CreditsSettingsTab: View {
    @Environment(\.colorScheme) private var colorScheme

    private var logo: NSImage? { AppAssets.logo(dark: colorScheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            if let logo {
                Image(nsImage: logo)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 230)
                    .accessibilityLabel("VFX Media")
            } else {
                Text("VFX MEDIA").font(.system(size: 30, weight: .heavy))
            }

            Text("RAW Select von \(AppInfo.author)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            HStack(spacing: 12) {
                BigLinkButton(title: "Instagram", subtitle: "@\(AppInfo.instagramHandle)",
                              url: AppInfo.instagramURL, icon: { InstagramGlyph() })
                BigLinkButton(title: "Website", subtitle: "vfxmedia.ch",
                              url: AppInfo.companyURL, icon: { WebsiteGlyph() })
            }
            .padding(.top, 28)

            HStack(spacing: 18) {
                TextLink(title: "Feedback senden", systemImage: "bubble.left", url: AppInfo.feedbackURL, emphasized: true)
                TextLink(title: "E-Mail", systemImage: "envelope", url: AppInfo.emailURL)
                TextLink(title: "Datenschutz", systemImage: "hand.raised", url: AppInfo.privacyURL)
            }
            .padding(.top, 22)

            Spacer(minLength: 12)

            VStack(spacing: 4) {
                Text("\(AppInfo.name) \(AppInfo.displayVersion)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                if AppInfo.isBeta {
                    Text("Beta – danke fürs Testen!")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Large tile link: icon, title, subtitle. Hover lifts the fill a notch, press scales to 0.97 —
/// the same feedback language as the native controls around it.
private struct BigLinkButton<Icon: View>: View {
    let title: String
    let subtitle: String
    let url: URL
    @ViewBuilder var icon: () -> Icon
    @State private var hovering = false

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 12) {
                icon().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(width: 196)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(url.absoluteString)
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Small secondary link: icon + text, underlined on hover. `emphasized` (feedback) uses the accent
/// colour so it stays findable without competing with the two big buttons.
private struct TextLink: View {
    let title: String
    let systemImage: String
    let url: URL
    var emphasized = false
    @State private var hovering = false

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.caption)
                Text(title).font(.callout).underline(hovering)
            }
            .foregroundStyle(emphasized ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

/// Instagram-style mark built from SF Symbols: camera on the brand gradient. No trademark artwork
/// is bundled — the gradient alone makes it recognisable.
private struct InstagramGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: "#FEDA75"), Color(hex: "#FA7E1E"), Color(hex: "#D62976"),
                                          Color(hex: "#962FBF"), Color(hex: "#4F5BD5")],
                                 startPoint: .bottomLeading, endPoint: .topTrailing))
            .overlay(Image(systemName: "camera").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
    }
}

private struct WebsiteGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.primary)
            .overlay(Image(systemName: "globe").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(nsColor: .windowBackgroundColor)))
    }
}
