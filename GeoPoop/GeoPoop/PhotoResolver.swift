//
//  PhotoResolver.swift
//  GeoPoop
//
//  Unified photo loading that transparently handles both locally-owned photos
//  and community bathroom photos that live in Supabase Storage.
//
//  ── Problem it Solves ─────────────────────────────────────────────────────
//
//  When user A syncs user B's bathroom, the local Bathroom model stores the
//  photo file names (photo_paths from the cloud), but the actual JPEG files
//  are only in Supabase Storage — NOT on user A's device. Any view that
//  calls ImageStorage.loadThumbnailAsync() directly will get nil for those
//  images, showing placeholder tiles forever.
//
//  PhotoResolver solves this by adding a cloud-download fallback: on a local
//  cache miss it downloads the image from Supabase Storage, saves it to the
//  local Documents directory under the same file name, then returns the
//  thumbnail. Future accesses are served from local disk (fast).
//
//  ── Usage ─────────────────────────────────────────────────────────────────
//
//    // In a .task modifier:
//    image = await PhotoResolver.thumbnail(
//        bathroomID: bathroom.id,
//        fileName:   fileName,
//        supabase:   supabaseService
//    )
//
//  ── Cache Layering ────────────────────────────────────────────────────────
//
//  1. NSCache (in-memory, managed by ImageStorage) — fastest
//  2. Local disk (Documents/BathroomImages/…)       — fast
//  3. Supabase Storage download                     — slow, one-time only
//
//  After step 3, the image lives in layers 1 and 2 for all future accesses.
//

import UIKit

enum PhotoResolver {

    // MARK: - Thumbnail

    /// Returns a thumbnail (≤ 200 px longest edge) for the given photo.
    ///
    /// Tries local disk/cache first. On a miss, downloads the full image from
    /// Supabase Storage, saves it locally (generating the thumbnail too), and
    /// returns the newly cached thumbnail. Returns nil only if the download
    /// also fails (e.g., the file doesn't exist in Storage yet).
    static func thumbnail(
        bathroomID: UUID,
        fileName:   String,
        supabase:   SupabaseService
    ) async -> UIImage? {
        // Fast path: already on disk / in memory
        if let local = await ImageStorage.loadThumbnailAsync(bathroomID: bathroomID, fileName: fileName) {
            return local
        }
        // Slow path: download from cloud and cache
        return await downloadAndCache(
            bathroomID: bathroomID,
            fileName:   fileName,
            supabase:   supabase,
            thumbnail:  true
        )
    }

    // MARK: - Full-Size

    /// Returns the full-resolution image (≤ 1200 px longest edge).
    ///
    /// Same two-step strategy as thumbnail(): local first, cloud fallback.
    static func fullSize(
        bathroomID: UUID,
        fileName:   String,
        supabase:   SupabaseService
    ) async -> UIImage? {
        if let local = await ImageStorage.loadImageAsync(bathroomID: bathroomID, fileName: fileName) {
            return local
        }
        return await downloadAndCache(
            bathroomID: bathroomID,
            fileName:   fileName,
            supabase:   supabase,
            thumbnail:  false
        )
    }

    // MARK: - Private

    /// Downloads a full-size image from Supabase Storage, saves it to local
    /// disk under the same file name (so ImageStorage can serve it next time),
    /// and returns either the thumbnail or full-size version from the local cache.
    private static func downloadAndCache(
        bathroomID: UUID,
        fileName:   String,
        supabase:   SupabaseService,
        thumbnail:  Bool
    ) async -> UIImage? {
        guard let downloaded = try? await supabase.downloadPhoto(
            bathroomID: bathroomID,
            fileName:   fileName
        ) else { return nil }

        // Persist under the EXACT same file name so ImageStorage.loadThumbnailAsync
        // finds it on the next access (no name mismatch between cloud and local).
        ImageStorage.saveDownloadedImage(downloaded, bathroomID: bathroomID, fileName: fileName)

        return thumbnail
            ? await ImageStorage.loadThumbnailAsync(bathroomID: bathroomID, fileName: fileName)
            : await ImageStorage.loadImageAsync(bathroomID: bathroomID, fileName: fileName)
    }
}
