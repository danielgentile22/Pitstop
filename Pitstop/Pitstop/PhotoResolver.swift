import UIKit

/// Loads bathroom photos from the local cache, downloading and caching them on a miss.
/// Synced community bathrooms carry photo file names whose files exist only on the server.
enum PhotoResolver {

    static func thumbnail(
        bathroomID: UUID,
        fileName:   String,
        supabase:   SupabaseService
    ) async -> UIImage? {
        if let local = await ImageStorage.loadThumbnailAsync(bathroomID: bathroomID, fileName: fileName) {
            return local
        }
        return await downloadAndCache(
            bathroomID: bathroomID,
            fileName:   fileName,
            supabase:   supabase,
            thumbnail:  true
        )
    }

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

        // Keep the server's file name so later local lookups hit.
        ImageStorage.saveDownloadedImage(downloaded, bathroomID: bathroomID, fileName: fileName)

        return thumbnail
            ? await ImageStorage.loadThumbnailAsync(bathroomID: bathroomID, fileName: fileName)
            : await ImageStorage.loadImageAsync(bathroomID: bathroomID, fileName: fileName)
    }
}
