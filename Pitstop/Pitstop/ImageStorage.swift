import ImageIO
import Synchronization
import UIKit

/// Bathroom photos on disk as JPEG pairs (full size and `_thumb`) under
/// Documents/BathroomImages/{bathroomID}/, fronted by in-memory caches.
/// Nonisolated so file reads, decoding, resizing and writes can run off the main actor;
/// the async entry points do that work on the global executor.
nonisolated enum ImageStorage {

    // MARK: - Configuration

    private static let rootFolderName        = "BathroomImages"
    private static let jpegQuality: CGFloat  = 0.80
    /// Longest edge in pixels.
    static let fullMaxDimension: CGFloat  = 1200
    private static let thumbMaxDimension: CGFloat = 200

    // MARK: - In-Memory Cache

    private static let thumbnailCache = NSCache<NSString, UIImage>()

    private static let fullImageCache = NSCache<NSString, UIImage>()

    // MARK: - Per-Bathroom Key Tracking

    // NSCache can't enumerate keys, so track them per bathroom to evict just one bathroom's entries.
    // Both caches' keys share one set; thumbnail keys carry a `_thumb` suffix.

    private static let keysByBathroom = Mutex<[UUID: Set<String>]>([:])

    // MARK: - Directory Helpers

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Documents/BathroomImages. Tests pass a temporary folder instead.
    static var defaultRoot: URL {
        documentsURL.appendingPathComponent(rootFolderName)
    }

    /// Only computes the path; `saveImage` is the one caller that creates the folder.
    private static func bathroomDirectory(id: UUID, root: URL = defaultRoot) -> URL {
        root.appendingPathComponent(id.uuidString)
    }

    // MARK: - Save

    enum WriteError: Error {
        case encodingFailed
    }

    /// Writes the full-size image and thumbnail atomically and returns the file name.
    /// Throws without leaving either file behind.
    static func saveImage(
        _ image: UIImage,
        bathroomID: UUID,
        root: URL = defaultRoot,
        fileName: String = "img_\(UUID().uuidString.prefix(8)).jpg"
    ) throws -> String {
        let dir      = bathroomDirectory(id: bathroomID, root: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fullURL  = dir.appendingPathComponent(fileName)
        let thumbURL = dir.appendingPathComponent(thumbnailName(for: fileName))

        let fullImage  = image.resized(toMaxPixels: fullMaxDimension)
        let thumbImage = image.resized(toMaxPixels: thumbMaxDimension)

        guard let fullData  = fullImage.jpegData(compressionQuality: jpegQuality),
              let thumbData = thumbImage.jpegData(compressionQuality: jpegQuality) else {
            throw WriteError.encodingFailed
        }

        try fullData.write(to: fullURL, options: .atomic)
        do {
            try thumbData.write(to: thumbURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: fullURL)
            throw error
        }

        cache(thumbImage, bathroomID: bathroomID, fileName: fileName, isThumb: true)
        cache(fullImage,  bathroomID: bathroomID, fileName: fileName, isThumb: false)
        return fileName
    }

    /// `saveImage` on the global executor, so resizing and encoding never block the interface.
    @concurrent
    static func saveImageAsync(_ image: UIImage, bathroomID: UUID, root: URL = defaultRoot) async throws -> String {
        try saveImage(image, bathroomID: bathroomID, root: root)
    }

    // MARK: - Load

    @concurrent
    static func loadThumbnailAsync(bathroomID: UUID, fileName: String) async -> UIImage? {
        load(bathroomID: bathroomID, fileName: fileName, isThumb: true)
    }

    @concurrent
    static func loadImageAsync(bathroomID: UUID, fileName: String) async -> UIImage? {
        load(bathroomID: bathroomID, fileName: fileName, isThumb: false)
    }

    /// Decodes picked image data straight to at most `fullMaxDimension` pixels on the long edge,
    /// so a large original is never held in memory at full size.
    @concurrent
    static func downsampledImage(from data: Data) async -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:   true,
            kCGImageSourceShouldCacheImmediately:         true,
            kCGImageSourceThumbnailMaxPixelSize:          fullMaxDimension,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Delete

    static func deleteImage(bathroomID: UUID, fileName: String, root: URL = defaultRoot) {
        let thumbKey = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: true)
        let fullKey  = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: false)
        thumbnailCache.removeObject(forKey: thumbKey as NSString)
        fullImageCache.removeObject(forKey: fullKey as NSString)
        keysByBathroom.withLock {
            $0[bathroomID]?.remove(thumbKey)
            $0[bathroomID]?.remove(fullKey)
        }

        let dir = bathroomDirectory(id: bathroomID, root: root)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(thumbnailName(for: fileName)))
    }

    static func deleteAllImages(bathroomID: UUID, root: URL = defaultRoot) {
        let keys = keysByBathroom.withLock { $0.removeValue(forKey: bathroomID) } ?? []
        for key in keys {
            thumbnailCache.removeObject(forKey: key as NSString)
            fullImageCache.removeObject(forKey: key as NSString)
        }

        try? FileManager.default.removeItem(at: bathroomDirectory(id: bathroomID, root: root))
    }

    // MARK: - Private Helpers

    static func thumbnailName(for fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return "\(base)_thumb.jpg"
    }

    private static func load(bathroomID: UUID, fileName: String, isThumb: Bool) -> UIImage? {
        let key   = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: isThumb) as NSString
        let cache = isThumb ? thumbnailCache : fullImageCache
        if let cached = cache.object(forKey: key) { return cached }
        let name = isThumb ? thumbnailName(for: fileName) : fileName
        let path = bathroomDirectory(id: bathroomID).appendingPathComponent(name).path
        // preparingForDisplay decodes now, on this thread, instead of lazily on the main thread at first draw.
        guard let image = UIImage(contentsOfFile: path)?.preparingForDisplay() else { return nil }
        self.cache(image, bathroomID: bathroomID, fileName: fileName, isThumb: isThumb)
        return image
    }

    private static func cache(_ image: UIImage, bathroomID: UUID, fileName: String, isThumb: Bool) {
        let key = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: isThumb)
        (isThumb ? thumbnailCache : fullImageCache).setObject(image, forKey: key as NSString)
        keysByBathroom.withLock { _ = $0[bathroomID, default: []].insert(key) }
    }

    private static func cacheKey(bathroomID: UUID, fileName: String, isThumb: Bool) -> String {
        "\(bathroomID)/\(fileName)\(isThumb ? "_thumb" : "")"
    }
}

// MARK: - UIImage Resize Helper

private nonisolated extension UIImage {

    /// Downscales so the longest edge is at most `maxPixels` pixels; never upscales.
    /// Renders at a scale of 1, so the output's pixel size is exactly the target size.
    func resized(toMaxPixels maxPixels: CGFloat) -> UIImage {
        let pixelSize   = CGSize(width: size.width * scale, height: size.height * scale)
        let longestEdge = max(pixelSize.width, pixelSize.height)
        guard longestEdge > maxPixels else { return self }

        let ratio   = maxPixels / longestEdge
        let newSize = CGSize(
            width:  (pixelSize.width  * ratio).rounded(),
            height: (pixelSize.height * ratio).rounded()
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
