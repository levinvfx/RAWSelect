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
        .background(WindowReader { app.browserWindow = $0 })
        // Drag a folder onto the window to load it.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            app.open(isDir.boolValue ? url : url.deletingLastPathComponent())
            return true
        }
        .overlay {
            if let op = app.operation {
                OperationOverlay(operation: op)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 46)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: app.toast)
        .sheet(isPresented: $app.showShortcuts) { ShortcutsSheet() }
        // ⌫ on more than one photo asks first (one photo goes straight away, culling stays fast).
        .confirmationDialog(
            "\(app.pendingTrash?.count ?? 0) Bilder in den Papierkorb?",
            isPresented: Binding(
                get: { app.pendingTrash != nil },
                set: { if !$0 { app.cancelTrash() } }
            ),
            titleVisibility: .visible
        ) {
            Button("In den Papierkorb", role: .destructive) { app.confirmTrash() }
            Button("Abbrechen", role: .cancel) { app.cancelTrash() }
        } message: {
            Text("Die Dateien (inkl. XMP) landen im macOS-Papierkorb und können dort wiederhergestellt werden.")
        }
    }
}

/// Hands the hosting NSWindow to AppState, so culling keys can tell the browser window apart
/// from the Settings window (both are titled windows that become key and main).
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView { ReaderView(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        let onWindow: (NSWindow?) -> Void
        init(onWindow: @escaping (NSWindow?) -> Void) { self.onWindow = onWindow; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let w = window
            DispatchQueue.main.async { self.onWindow(w) }
        }
    }
}
