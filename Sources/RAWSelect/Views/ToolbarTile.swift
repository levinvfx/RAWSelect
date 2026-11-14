import SwiftUI

enum ToolbarTileMetrics {
    static let spacing: CGFloat = 6
    static let groupGap: CGFloat = 4
}

/// An icon button with its own visible tile, so the four actions on the right of the toolbar read
/// as four separate buttons. Darker on hover and press, dimmed when the action isn't available.
struct ToolbarTile<Icon: View>: View {
    /// Tooltip and VoiceOver name.
    let title: String
    var disabled = false
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon().accessibilityLabel(title)
        }
        .buttonStyle(TileStyle())
        .disabled(disabled)
        .help(title)
        // Each tile is its own toolbar item now; this keeps the gap between them.
        .padding(.horizontal, ToolbarTileMetrics.spacing / 2)
    }
}

private struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration)
    }

    private struct Tile: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        private var fill: Double {
            guard isEnabled else { return 0.06 }
            if configuration.isPressed { return 0.22 }
            return hovering ? 0.15 : 0.09
        }

        var body: some View {
            configuration.label
                .foregroundStyle(Color.primary.opacity(0.9))
                .opacity(isEnabled ? 1 : 0.5)      // on the whole label: the logos are in colour
                .frame(width: 38, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(fill)))
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
