import SwiftUI

/// Modal progress overlay shown during copy/move operations.
struct OperationOverlay: View {
    @EnvironmentObject var app: AppState
    let operation: AppState.OperationState

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 16) {
                Text(operation.title)
                    .font(.headline)

                if operation.total > 0 {
                    ProgressView(value: Double(operation.completed), total: Double(operation.total))
                        .frame(width: 280)
                    Text("\(operation.completed) / \(operation.total) Dateien")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(width: 280)
                }

                Button("Abbrechen", role: .cancel) { app.cancelOperation() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 24)
        }
    }
}
