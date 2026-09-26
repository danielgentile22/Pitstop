import UIKit

/// Bathroom photos on disk as JPEG pairs (full size and `_thumb`) under
/// Documents/BathroomImages/{bathroomID}/, fronted by in-memory caches.
enum ImageStorage {

    // MARK: - Configuration

    private static let rootFolderName        = "BathroomImages"
    private static let jpegQuality: CGFloat  = 0.80
    private static let fullMaxDimension: CGFloat  = 1200
    private static let thumbMaxDimension: CGFloat = 200

    // MARK: - In-Memory Cache

    private static let thumbnailCache = NSCache<NSString, UIImage>()

    private static let fullImageCache = NSCache<NSString, UIImage>()

    // MARK: - Per-Bathroom Key Tracking

    // NSCache can't enumerate keys, so track them per bathroom to evict just one bathroom's entries.

    private static var thumbKeysByBathroom: [UUID: Set<NSString>] = [:]
    private static var fullKeysByBathroom:  [UUID: Set<NSString>] = [:]

    // MARK: - Directory Helpers

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Creates the directory if needed.
    private static func bathroomDirectory(id: UUID) throws -> URL {
        let dir = documentsURL
            .appendingPathComponent(rootFolderName)
            .appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Save

    /// Writes the full-size image and thumbnail and returns the generated file name.
    @discardableResult
    static func saveImage(_ image: UIImage, bathroomID: UUID) -> String? {
        guard let dir = try? bathroomDirectory(id: bathroomID) else { return nil }

        let token    = UUID().uuidString.prefix(8)
        let fileName = "img_\(token).jpg"
        return write(image, bathroomID: bathroomID, fileName: fileName, dir: dir)
    }

    /// Saves a downloaded image under the file name the server recorded. No-op if already on disk.
    @discardableResult
    static func saveDownloadedImage(_ image: UIImage, bathroomID: UUID, fileName: String) -> Bool {
        guard let dir = try? bathroomDirectory(id: bathroomID) else { return false }

        let fullURL = dir.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: fullURL.path) else { return true }

        return write(image, bathroomID: bathroomID, fileName: fileName, dir: dir) != nil
    }

    // MARK: - Write

    @discardableResult
    private static func write(_ image: UIImage, bathroomID: UUID, fileName: String, dir: URL) -> String? {
        let fullURL  = dir.appendingPathComponent(fileName)
        let thumbURL = dir.appendingPathComponent(thumbnailName(for: fileName))

        let fullImage  = image.resized(toMaxDimension: fullMaxDimension)
        let thumbImage = image.resized(toMaxDimension: thumbMaxDimension)

        guard let fullData  = fullImage.jpegData(compressionQuality: jpegQuality),
              let thumbData = thumbImage.jpegData(compressionQuality: jpegQuality) else {
            return nil
        }

        do {
            try fullData.write(to: fullURL)
            try thumbData.write(to: thumbURL)

            let thumbKey = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: true)
            let fullKey  = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: false)
            thumbnailCache.setObject(thumbImage, forKey: thumbKey)
            fullImageCache.setObject(fullImage,  forKey: fullKey)
            registerKey(thumbKey, forBathroom: bathroomID, isThumb: true)
            registerKey(fullKey,  forBathroom: bathroomID, isThumb: false)
            return fileName
        } catch {
            return nil
        }
    }

    // MARK: - Load

    static func loadThumbnail(bathroomID: UUID, fileName: String) -> UIImage? {
        let key = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: true)
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let dir = try? bathroomDirectory(id: bathroomID) else { return nil }
        let path = dir.appendingPathComponent(thumbnailName(for: fileName)).path
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        thumbnailCache.setObject(image, forKey: key)
        registerKey(key, forBathroom: bathroomID, isThumb: true)
        return image
    }

    static func loadImage(bathroomID: UUID, fileName: String) -> UIImage? {
        let key = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: false)
        if let cached = fullImageCache.object(forKey: key) { return cached }
        guard let dir = try? bathroomDirectory(id: bathroomID) else { return nil }
        let path = dir.appendingPathComponent(fileName).path
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        fullImageCache.setObject(image, forKey: key)
        registerKey(key, forBathroom: bathroomID, isThumb: false)
        return image
    }

    static func loadThumbnailAsync(bathroomID: UUID, fileName: String) async -> UIImage? {
        let key = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: true)
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        return loadThumbnail(bathroomID: bathroomID, fileName: fileName)
    }

    static func loadImageAsync(bathroomID: UUID, fileName: String) async -> UIImage? {
        let key = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: false)
        if let cached = fullImageCache.object(forKey: key) { return cached }
        return loadImage(bathroomID: bathroomID, fileName: fileName)
    }

    // MARK: - Delete

    static func deleteImage(bathroomID: UUID, fileName: String) {
        let thumbKey = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: true)
        let fullKey  = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: false)
        thumbnailCache.removeObject(forKey: thumbKey)
        fullImageCache.removeObject(forKey: fullKey)
        thumbKeysByBathroom[bathroomID]?.remove(thumbKey)
        fullKeysByBathroom[bathroomID]?.remove(fullKey)

        guard let dir = try? bathroomDirectory(id: bathroomID) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(thumbnailName(for: fileName)))
    }

    static func deleteAllImages(bathroomID: UUID) {
        for key in thumbKeysByBathroom[bathroomID] ?? [] { thumbnailCache.removeObject(forKey: key) }
        for key in fullKeysByBathroom[bathroomID]  ?? [] { fullImageCache.removeObject(forKey: key) }
        thumbKeysByBathroom.removeValue(forKey: bathroomID)
        fullKeysByBathroom.removeValue(forKey: bathroomID)

        let dir = documentsURL
            .appendingPathComponent(rootFolderName)
            .appendingPathComponent(bathroomID.uuidString)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Private Helpers

    private static func thumbnailName(for fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return "\(base)_thumb.jpg"
    }

    private static func cacheKey(bathroomID: UUID, fileName: String, isThumb: Bool) -> NSString {
        "\(bathroomID)/\(fileName)\(isThumb ? "_thumb" : "")" as NSString
    }

    private static func registerKey(_ key: NSString, forBathroom id: UUID, isThumb: Bool) {
        if isThumb {
            thumbKeysByBathroom[id, default: []].insert(key)
        } else {
            fullKeysByBathroom[id, default: []].insert(key)
        }
    }
}

// MARK: - UIImage Resize Helper

private extension UIImage {

    /// Downscales so the longest edge is at most `maxDimension`; never upscales.
    func resized(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxDimension else { return self }

        let scale   = maxDimension / longestEdge
        let newSize = CGSize(
            width:  (size.width  * scale).rounded(),
            height: (size.height * scale).rounded()
        )

        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
