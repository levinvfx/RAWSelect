import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List(selection: filterSelection) {
            Section("Datenträger") {
                if app.volumes.isEmpty {
                    Text("Keine externen Datenträger")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(app.volumes) { volume in
                    Button { app.open(volume.url) } label: {
                        Label(volume.name, systemImage: "sdcard")
                    }
                    .buttonStyle(.plain)
                }
                Button { app.openFolderDialog() } label: {
                    Label("Ordner öffnen…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
            }

            if let browseRoot = app.browseRoot {
                Section("Ordner") {
                    FolderNavigator(root: browseRoot)
                }
            }

            Section("Filter") {
                filterRow(title: "Alle Bilder", systemImage: "photo.on.rectangle", count: app.groups.count)
                    .tag(PhotoFilter.all)
                filterRow(title: "Unmarkiert", systemImage: "circle.dashed", count: app.unmarkedCount)
                    .tag(PhotoFilter.unmarked)
                filterRow(title: "Ausschuss", systemImage: "xmark.circle", tint: .red, count: app.rejectCount)
                    .tag(PhotoFilter.reject)
            }

            Section("Sterne") {
                ForEach((1...5).reversed(), id: \.self) { stars in
                    filterRow(title: "\(stars)+ Sterne", stars: stars, count: app.ratingCounts[stars] ?? 0)
                        .tag(PhotoFilter.rating(stars))
                }
            }

            Section("Markierungen") {
                ForEach(1...9, id: \.self) { mark in
                    filterRow(title: "Markierung \(mark)", dot: MarkStyle.color(for: mark),
                              count: app.markCounts[mark] ?? 0)
                        .tag(PhotoFilter.mark(mark))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppInfo.name)
    }

    private var filterSelection: Binding<PhotoFilter?> {
        Binding(get: { app.filter }, set: { if let f = $0 { app.filter = f } })
    }

    @ViewBuilder
    private func filterRow(title: String, systemImage: String? = nil, tint: Color? = nil,
                           dot: Color? = nil, stars: Int? = nil, count: Int) -> some View {
        HStack(spacing: 8) {
            if let dot {
                Circle().fill(dot).frame(width: 10, height: 10)
            } else if let stars {
                HStack(spacing: 1) {
                    ForEach(0..<stars, id: \.self) { _ in
                        Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow)
                    }
                }
                .frame(width: 46, alignment: .leading)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint ?? .secondary)
                    .frame(width: 16)
            }
            Text(title)
            Spacer()
            if count > 0 {
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}
