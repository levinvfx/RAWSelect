import SwiftUI
import AppKit

/// Custom entry point so we can run a headless self-test of the core workflow
/// (`--selftest`) before falling through to the normal SwiftUI app launch.
@main
enum EntryPoint {
    static func main() {
        #if DEBUG
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            exit(0)
        }
        #endif
        if let idx = CommandLine.arguments.firstIndex(of: "--rawcheck") {
            RawCheck.run(Array(CommandLine.arguments[(idx + 1)...]))
            exit(0)
        }
        #if DEBUG
        if let idx = CommandLine.arguments.firstIndex(of: "--slidercal") {
            SliderCal.run(Array(CommandLine.arguments[(idx + 1)...]))
            exit(0)
        }
        #endif
        RAWSelectApp.main()
    }
}

struct RAWSelectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var updater = UpdateController()

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            ContentView()
                .environmentObject(app)
                .environmentObject(settings)
                .environmentObject(updater)
                .frame(minWidth: 1040, minHeight: 660)
                .sheet(isPresented: $updater.showSheet) {
                    UpdateSheet().environmentObject(updater)
                }
                .task { updater.checkOnLaunch() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen…") { updater.checkManually() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Ordner öffnen…") { app.openFolderDialog() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Im Finder anzeigen") { app.revealCurrent() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        // Native macOS Settings window: RAW Select → Settings… (⌘,)
        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.systemColorScheme)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        // Development builds keep the Lightroom bridge plug-in current at its stable path.
        // The public app ships no plug-in and never touches Application Support.
        BridgeInstaller.installIfNeeded()
        #endif
        TelemetryService.askOnFirstRunIfNeeded()   // einmalig fragen, BEVOR das erste Mal gesendet wird
        TelemetryService.pingIfEnabled()            // anonym, opt-out, max. 1×/Tag
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Flush unsaved marks before the process dies. Marks are written asynchronously, so
    /// rating the last photo and immediately pressing ⌘Q (or closing the window) could drop
    /// that final mark — the one moment culling data loss is most likely. This runs on the
    /// main thread at termination, so it's safe to reach the main-actor AppState directly.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppState.shared?.flushPendingWrites()
        }
    }
}
