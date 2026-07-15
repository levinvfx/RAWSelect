import SwiftUI

/// Standalone, non-destructive editor for a single photo, reachable straight from
/// the browser (toolbar button or the `E` key) — no export needed. It edits a
/// local draft; "Fertig" commits it to `AppState.edits` (and persists), while
/// "Abbrechen" / Esc discards. The same edit later flows into the export.
struct ImageEditorSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let group: PhotoGroup

    @State private var draft = ImageEdit()
    @State private var editorTab: EditorTab = .crop

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.below.rectangle")
                Text("Bearbeiten").font(.title3.weight(.semibold))
                Text(group.displayName)
                    .font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Alles zurücksetzen") { draft = ImageEdit() }
                    .disabled(draft.isIdentity)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()

            CropEditorView(previewURL: group.previewURL, edit: $draft, editorTab: $editorTab)
                .padding(20)

            Divider()
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Fertig") { app.commitEdit(draft, for: group.id); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 760, height: 760)
        .onAppear { draft = app.edit(for: group.id) }
    }
}
