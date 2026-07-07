import SwiftUI

/// Native macOS Settings window (RAW Select → Settings…, ⌘,). Deliberately
/// reduced to a small, curated set of options.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab().tabItem { Label("Allgemein", systemImage: "gearshape") }
            SourcesSettingsTab().tabItem { Label("Quellen", systemImage: "sdcard") }
            ViewSettingsTab().tabItem { Label("Ansicht", systemImage: "photo") }
            MarkSettingsTab().tabItem { Label("Markierungen", systemImage: "tag") }
            ExportSettingsTab().tabItem { Label("Export", systemImage: "square.and.arrow.up") }
            AdvancedSettingsTab().tabItem { Label("Erweitert", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 500, height: 440)
    }
}

// MARK: - Reusable rows

/// Toggle with a title and an optional secondary help line.
struct SettingToggle: View {
    let title: String
    var help: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let help { Text(help).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// A labelled picker with an optional help line beneath.
struct SettingPicker<T: Hashable, Content: View>: View {
    let title: String
    var help: String? = nil
    @Binding var selection: T
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: $selection) { content() }
            if let help { Text(help).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
