import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 320)
        } detail: {
            DetailView()
        }
        .preferredColorScheme(settings.systemColorScheme)
        .onAppear { app.start() }
        .overlay {
            if let op = app.operation {
                OperationOverlay(operation: op)
            }
        }
        .confirmationDialog(
            "Markierte Bilder verschieben?",
            isPresented: Binding(
                get: { app.pendingMoveTarget != nil },
                set: { if !$0 { app.cancelMove() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Verschieben", role: .destructive) { app.confirmMove() }
            Button("Abbrechen", role: .cancel) { app.cancelMove() }
        } message: {
            Text("\(app.selectionCount) Bilder werden aus dem Quellordner entfernt und in den Zielordner verschoben. Die Originale bleiben nicht am ursprünglichen Ort.")
        }
    }
}
