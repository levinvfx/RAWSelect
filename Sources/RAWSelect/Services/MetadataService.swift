import Foundation
import ImageIO

/// Reads EXIF/TIFF metadata for the info overlay. Fast (only headers) and cached.
struct PhotoMetadata {
    var camera: String?
    var lens: String?
    var focalLength: String?
    var aperture: String?
    var shutter: String?
    var iso: String?
    var dateTime: String?
    var pixels: String?

    /// Ordered (label, value) rows for display, skipping empty values.
    var rows: [(String, String)] {
        var r: [(String, String)] = []
        func add(_ label: String, _ value: String?) { if let v = value, !v.isEmpty { r.append((label, v)) } }
        add("Kamera", camera)
        add("Objektiv", lens)
        add("Brennweite", focalLength)
        add("Blende", aperture)
        add("Zeit", shutter)
        add("ISO", iso)
        add("Aufnahme", dateTime)
        add("Pixel", pixels)
        return r
    }
}

enum MetadataService {
    private static let cache = NSCache<NSString, CacheBox>()
    private final class CacheBox { let value: PhotoMetadata; init(_ v: PhotoMetadata) { value = v } }

    static func metadata(for url: URL) -> PhotoMetadata {
        let key = url.path as NSString
        if let box = cache.object(forKey: key) { return box.value }
        let meta = read(url)
        cache.setObject(CacheBox(meta), forKey: key)
        return meta
    }

    private static func read(_ url: URL) -> PhotoMetadata {
        var meta = PhotoMetadata()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return meta
        }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let exifAux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        let make = tiff[kCGImagePropertyTIFFMake] as? String
        let model = tiff[kCGImagePropertyTIFFModel] as? String
        meta.camera = [make, model].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)

        meta.lens = (exif[kCGImagePropertyExifLensModel] as? String)
            ?? (exifAux[kCGImagePropertyExifAuxLensModel] as? String)

        if let f = exif[kCGImagePropertyExifFocalLength] as? Double {
            meta.focalLength = "\(Int(f.rounded())) mm"
        }
        if let a = exif[kCGImagePropertyExifFNumber] as? Double {
            meta.aperture = "ƒ/\(String(format: "%g", a))"
        }
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            meta.shutter = t >= 1 ? "\(String(format: "%g", t)) s" : "1/\(Int((1/t).rounded())) s"
        }
        if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoArray.first {
            meta.iso = "\(iso)"
        }
        if let d = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            meta.dateTime = formatDate(d)
        }
        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            meta.pixels = "\(w) × \(h)"
        }
        return meta
    }

    /// EXIF dates look like "2025:07:04 13:54:02" → "04.07.2025 13:54".
    private static func formatDate(_ raw: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = inFmt.date(from: raw) else { return raw }
        let outFmt = DateFormatter()
        outFmt.dateFormat = "dd.MM.yyyy HH:mm"
        return outFmt.string(from: date)
    }
}
