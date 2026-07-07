import SwiftUI

/// Native macOS Settings window (opened via RAW Select → Settings…, ⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab().tabItem { Label("Allgemein", systemImage: "gearshape") }
            SourcesSettingsTab().tabItem { Label("Quellen", systemImage: "sdcard") }
            ViewSettingsTab().tabItem { Label("Ansicht & Preview", systemImage: "photo") }
            MarkSettingsTab().tabItem { Label("Markierungen", systemImage: "tag") }
            ExportSettingsTab().tabItem { Label("Export & Dateien", systemImage: "square.and.arrow.up") }
            PerformanceSettingsTab().tabItem { Label("Performance & Cache", systemImage: "speedometer") }
            AppearanceSettingsTab().tabItem { Label("Darstellung", systemImage: "paintbrush") }
            AdvancedSettingsTab().tabItem { Label("Erweitert", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 580, height: 560)
    }
}

// MARK: - Reusable rows

/// Toggle with a title and an optional secondary help line.
struct SettingToggle: View {
    let title: String
    var help: String? = nil
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let help { Text(help).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .disabled(disabled)
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

/// Static informational note row.
struct SettingNote: View {
    let text: String
    var systemImage: String = "info.circle"
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
