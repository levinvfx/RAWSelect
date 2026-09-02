import Foundation
import AppKit

/// Lists mounted external volumes and watches for mount/unmount events.
final class VolumeScanner {

    /// External / removable volumes suitable to show as "SD cards / drives".
    static func externalVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey,
            .volumeIsEjectableKey, .volumeIsBrowsableKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        var result: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.volumeIsBrowsable == true else { continue }

            let removable = values.volumeIsRemovable == true
            let ejectable = values.volumeIsEjectable == true
            let external = removable || ejectable || (values.volumeIsInternal == false)
            guard external else { continue }   // hide the internal boot drive

            let name = values.volumeName ?? url.lastPathComponent
            result.append(VolumeInfo(id: url.path, name: name, url: url, isExternal: true))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var observers: [NSObjectProtocol] = []

    /// Calls `onChange` on the main queue whenever a volume mounts/unmounts/renames, and
    /// `onUnmount(volumeURL)` when one disappears — so the app can react if it was the open one.
    func startWatching(onChange: @escaping () -> Void, onUnmount: @escaping (URL) -> Void = { _ in }) {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                if name == NSWorkspace.didUnmountNotification,
                   let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                    onUnmount(url)
                }
                onChange()
            }
            observers.append(token)
        }
    }

    func stopWatching() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    deinit { stopWatching() }
}
