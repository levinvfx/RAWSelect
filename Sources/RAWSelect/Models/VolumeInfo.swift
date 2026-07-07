import Foundation

/// A mounted volume shown in the sidebar (SD cards / external drives).
struct VolumeInfo: Identifiable, Hashable {
    let id: String        // volume path, stable per mount
    let name: String
    let url: URL
    let isExternal: Bool  // removable / ejectable / non-internal
}

extension URL {
    /// Whether this URL lives on a removable / external volume (SD card, USB…).
    /// Used to protect originals: moving off an external source is disabled.
    var isOnExternalVolume: Bool {
        let keys: Set<URLResourceKey> = [
            .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey
        ]
        guard let values = try? resourceValues(forKeys: keys) else { return false }
        if values.volumeIsRemovable == true { return true }
        if values.volumeIsEjectable == true { return true }
        if let internalVol = values.volumeIsInternal { return internalVol == false }
        return false
    }
}
