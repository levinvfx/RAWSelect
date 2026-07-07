import SwiftUI

/// Small, neutral "Ps" badge signalling the Photoshop-powered export. Deliberately
/// generic – not the official Adobe/Photoshop logo.
struct PsBadge: View {
    var body: some View {
        Text("Ps")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 22, height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.16, green: 0.21, blue: 0.34)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            .accessibilityLabel("Photoshop-Export")
    }
}
