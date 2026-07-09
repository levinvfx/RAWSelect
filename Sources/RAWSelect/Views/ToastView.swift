import SwiftUI

/// A small, non-interactive confirmation/error banner shown briefly after an
/// action (copy, move, export, error). Purely visual feedback.
struct ToastView: View {
    let toast: AppState.Toast

    private var color: Color {
        switch toast.kind {
        case .success: return .green
        case .error:   return .red
        case .info:    return .accentColor
        }
    }
    private var icon: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(toast.message).font(.callout).lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}
