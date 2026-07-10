import SwiftUI

/// The auto-update dialog, driven by `UpdateController.phase`.
struct UpdateSheet: View {
    @EnvironmentObject var updater: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch updater.phase {
            case .checking:
                row { ProgressView().controlSize(.small); Text("Suche nach Updates…") }

            case .upToDate:
                Label("\(AppInfo.name) ist aktuell (Version \(AppInfo.version)).",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                closeButtons

            case .available(let info):
                Text("Version \(info.version) verfügbar").font(.title3.weight(.semibold))
                Text("Installiert ist \(AppInfo.version).")
                    .font(.callout).foregroundStyle(.secondary)
                if !info.notes.isEmpty {
                    ScrollView {
                        Text(info.notes)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 220)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Spacer()
                    Button("Später") { updater.dismiss() }
                    Button("Herunterladen & installieren") { updater.download() }
                        .keyboardShortcut(.defaultAction)
                }

            case .downloading:
                row { ProgressView().controlSize(.small); Text("Lädt Update herunter…") }
                Text("Das DMG öffnet sich anschliessend im Finder.")
                    .font(.caption).foregroundStyle(.secondary)

            case .failed(let msg):
                Label("Update fehlgeschlagen", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(msg).font(.callout).foregroundStyle(.secondary)
                closeButtons

            case .idle:
                EmptyView()
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
    }

    private var closeButtons: some View {
        HStack {
            Spacer()
            Button("OK") { updater.dismiss() }.keyboardShortcut(.defaultAction)
        }
    }
}
