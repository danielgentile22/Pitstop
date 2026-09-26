//
//  ImageStorage.swift
//  Pitstop
//
//  File-based photo storage for bathroom images.
//  All images are stored as JPEGs in the app's Documents directory.
//
//  Storage layout:
//    Documents/
//    └── BathroomImages/
//        └── {bathroom-uuid}/
//            ├── img_{token}.jpg          ← full-size (max 1200px longest edge)
//            └── img_{token}_thumb.jpg    ← thumbnail (200px longest edge)
//
//  Caching:
//    An NSCache layer keeps recently accessed images in memory so repeated
//    accesses during list scrolling don't hit disk. Entries are evicted
//    automatically under memory pressure.
//
//    Key tracking: `thumbKeysByBathroom` and `fullKeysByBathroom` map each
//    bathroom UUID to its set of cache keys. This allows `deleteAllImages`
//    to evict only that bathroom's entries rather than flushing the entire
//    cache (the prior behaviour, which caused all visible thumbnails to reload
//    from disk whenever ANY bathroom was deleted).
//
//  Async variants:
//    loadThumbnailAsync / loadImageAsync run the disk read on a background
//    thread (Task.detached) so SwiftUI views can load images without
//    blocking the main thread.
//
//  saveDownloadedImage:
//    A second save entry-point (in addition to saveImage) that accepts an
//    EXISTING file name rather than generating a new one. Used by PhotoResolver
//    to persist community photos that were downloaded from Supabase Storage
//    under the same file name the cloud recorded.
//

import UIKit

/// Static helpers for saving, loading, and deleting bathroom photos on disk.
enum ImageStorage {

    // MARK: - Configuration

    private static let rootFolderName        = "BathroomImages"
    private static let jpegQuality: CGFloat  = 0.80
    private static let fullMaxDimension: CGFloat  = 1200
    private static let thumbMaxDimension: CGFloat = 200

    // MARK: - In-Memory Cache

    /// Thumbnail cache — keyed by "{bathroomID}/{fileName}_thumb".
    private static let thumbnailCache = NSCache<NSString, UIImage>()

    /// Full-size image cache — keyed by "{bathroomID}/{fileName}".
    private static let fullImageCache = NSCache<NSString, UIImage>()

    // MARK: - Per-Bathroom Key Tracking
    //
    // NSCache does not support key enumeration, so we maintain parallel
    // dictionaries that map each bathroom UUID to the set of cache keys
    // it has contributed. deleteAllImages() uses these to evict precisely
    // the right entries without flushing the entire cache.

    private static var thumbKeysByBathroom: [UUID: Set<NSString>] = [:]
    private static var fullKeysByBathroom:  [UUID: Set<NSString>] = [:]

    // MARK: - Directory Helpers

    /// URL of the app's Documents directory.
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Returns (and creates if needed) the directory for a specific bathroom's images.
    private static func bathroomDirectory(id: UUID) throws -> URL {
        let dir = documentsURL
            .appendingPathComponent(rootFolderName)
            .appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Save (new image — generates file name)

    /// Saves an image for a bathroom and returns the generated file name.
    ///
    /// Two files are written: the full-size image and a thumbnail.
    /// Both are cached in memory immediately after saving.
    @discardableResult
    static func saveImage(_ image: UIImage, bathroomID: UUID) -> String? {
        guard let dir = try? bathroomDirectory(id: bathroomID) else { return nil }

        let token    = UUID().uuidString.prefix(8)
        let fileName = "img_\(token).jpg"
        return write(image, bathroomID: bathroomID, fileName: fileName, dir: dir)
    }

    // MARK: - Save (downloaded community image — uses existing file name)

    /// Saves a cloud-downloaded image under its existing file name.
    ///
    /// Called by PhotoResolver when a community bathroom photo is downloaded
    /// from Supabase Storage. Using the cloud file name ensures that subsequent
    /// calls to loadThumbnailAsync / loadImageAsync with that same name find
    /// the file locally, completing the local-first cache hierarchy.
    ///
    /// No-ops if the file already exists on disk (re-download protection).
    @discardableResult
    static func saveDownloadedImage(_ image: UIImage, bathroomID: UUID, fileName: String) -> Bool {
        guard let dir = try? bathroomDirectory(id: bathroomID) else { return false }

        // Skip if the full-size file is already on disk (prevents redundant writes
        // during rapid photo loads from the same community bathroom in the same session)
        let fullURL = dir.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: fullURL.path) else { return true }

        return write(image, bathroomID: bathroomID, fileName: fileName, dir: dir) != nil
    }

    // MARK: - Shared Write Helper

    /// Resizes, encodes, and writes the full-size + thumbnail pair to disk,
    /// then populates both caches and registers the keys for the bathroom.
    /// Returns the file name on success, nil on failure.
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

    // MARK: - Load (synchronous — use async variants in views)

    /// Loads the thumbnail for a given file name. Checks the in-memory cache first.
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

    /// Loads the full-size image for a given file name. Checks the in-memory cache first.
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

    // MARK: - Load (async — preferred for SwiftUI views)

    /// Loads a thumbnail, checking the in-memory cache first. Safe to call from a `.task` modifier.
    static func loadThumbnailAsync(bathroomID: UUID, fileName: String) async -> UIImage? {
        let key = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: true)
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        return loadThumbnail(bathroomID: bathroomID, fileName: fileName)
    }

    /// Loads a full-size image, checking the in-memory cache first. Safe to call from a `.task` modifier.
    static func loadImageAsync(bathroomID: UUID, fileName: String) async -> UIImage? {
        let key = cacheKey(bathroomID: bathroomID, fileName: fileName, isThumb: false)
        if let cached = fullImageCache.object(forKey: key) { return cached }
        return loadImage(bathroomID: bathroomID, fileName: fileName)
    }

    // MARK: - Delete

    /// Deletes a single image and its thumbnail from disk and cache.
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

    /// Deletes the entire image folder for a bathroom and evicts only its cache entries.
    ///
    /// Previously this flushed the ENTIRE cache (all bathrooms), causing every
    /// visible thumbnail to reload from disk when any bathroom was deleted. The
    /// new implementation uses the per-bathroom key registry to evict precisely
    /// the right entries.
    static func deleteAllImages(bathroomID: UUID) {
        // Evict only this bathroom's cache entries — leave other bathrooms' images intact
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

    /// Returns a copy of the image scaled so its longest edge is ≤ `maxDimension`.
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
