import Photos
import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case screenshots = "Screenshots"
    case videos = "Videos"

    var id: String { rawValue }
}

@MainActor
final class PhotoLibrary: ObservableObject {
    enum Decision { case keep, archive }

    @Published private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var queue: [PHAsset] = []
    @Published private(set) var archived: [PHAsset] = []
    @Published private(set) var canUndo = false
    @Published private(set) var freedBytes: Int64 = 0
    @Published private(set) var deletedCount = 0
    @Published var errorMessage: String?
    @Published var filter: LibraryFilter = .all {
        didSet { reloadQueue() }
    }

    /// How many unreviewed items to load into the swipe stack at once.
    private let batchSize = 300
    private let store = DecisionStore()
    private var history: [(asset: PHAsset, decision: Decision)] = []

    init() {
        freedBytes = store.freedBytes
        deletedCount = store.deletedCount
        if isAuthorized { reload() }
    }

    var isAuthorized: Bool { status == .authorized || status == .limited }
    var reviewedCount: Int { store.kept.count + store.archived.count + store.deletedCount }

    // MARK: - Access

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if isAuthorized { reload() }
    }

    /// Called when the app comes back to the foreground.
    func refreshStatus() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current != status {
            status = current
            if isAuthorized { reload() }
        } else if isAuthorized {
            reloadArchive()
        }
    }

    // MARK: - Loading

    func reload() {
        reloadQueue()
        reloadArchive()
    }

    func reloadQueue() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch filter {
        case .all:
            options.predicate = NSPredicate(
                format: "mediaType == %d OR mediaType == %d",
                PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
            )
        case .screenshots:
            options.predicate = NSPredicate(
                format: "(mediaSubtypes & %d) != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
        case .videos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        }

        let result = PHAsset.fetchAssets(with: options)
        let store = self.store
        let limit = batchSize
        var items: [PHAsset] = []
        result.enumerateObjects { asset, _, stop in
            if !store.isReviewed(asset.localIdentifier) {
                items.append(asset)
                if items.count >= limit { stop.pointee = true }
            }
        }
        queue = items
        history.removeAll()
        canUndo = false
    }

    func reloadArchive() {
        let ids = Array(store.archived)
        guard !ids.isEmpty else {
            archived = []
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
        var items: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in items.append(asset) }

        // Drop IDs for items that were deleted outside the app.
        let found = Set(items.map(\.localIdentifier))
        let missing = ids.filter { !found.contains($0) }
        if !missing.isEmpty { store.removeFromArchive(missing) }

        archived = items
    }

    // MARK: - Decisions

    func decide(_ decision: Decision, on asset: PHAsset) {
        let id = asset.localIdentifier
        queue.removeAll { $0.localIdentifier == id }
        switch decision {
        case .keep:
            store.keep(id)
        case .archive:
            store.archive(id)
            archived.insert(asset, at: 0)
        }
        history.append((asset, decision))
        if history.count > 100 { history.removeFirst() }
        canUndo = true

        if queue.isEmpty { reloadQueue() }
    }

    func undo() {
        guard let last = history.popLast() else { return }
        let id = last.asset.localIdentifier
        store.forget(id)
        archived.removeAll { $0.localIdentifier == id }
        queue.insert(last.asset, at: 0)
        canUndo = !history.isEmpty
    }

    func restore(_ asset: PHAsset) {
        store.keep(asset.localIdentifier)
        archived.removeAll { $0.localIdentifier == asset.localIdentifier }
    }

    func restoreAll() {
        for asset in archived { store.keep(asset.localIdentifier) }
        archived = []
    }

    func resetProgress() {
        store.resetAll()
        freedBytes = 0
        deletedCount = 0
        archived = []
        reloadQueue()
    }

    // MARK: - Photo library changes

    func toggleFavorite(_ asset: PHAsset) async {
        let newValue = !asset.isFavorite
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).isFavorite = newValue
            }
            let id = asset.localIdentifier
            if let fresh = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
               let index = queue.firstIndex(where: { $0.localIdentifier == id }) {
                queue[index] = fresh
            }
        } catch {
            errorMessage = "Couldn't update favorite: \(error.localizedDescription)"
        }
    }

    /// Deletes everything in the archive. iOS shows its own confirmation
    /// dialog, and deleted items go to "Recently Deleted" for 30 days.
    func deleteArchived() async {
        let assets = archived
        guard !assets.isEmpty else { return }
        let bytes = await Self.totalSize(of: assets)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            store.removeFromArchive(assets.map(\.localIdentifier))
            store.freedBytes += bytes
            store.deletedCount += assets.count
            freedBytes = store.freedBytes
            deletedCount = store.deletedCount
            archived = []
        } catch {
            let cancelled = (error as? PHPhotosError)?.code == .userCancelled
            if !cancelled {
                errorMessage = "Couldn't delete: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sizes

    nonisolated static func fileSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(Int64(0)) { total, resource in
            total + ((resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
        }
    }

    nonisolated static func totalSize(of assets: [PHAsset]) async -> Int64 {
        await Task.detached(priority: .utility) {
            assets.reduce(Int64(0)) { $0 + PhotoLibrary.fileSize(of: $1) }
        }.value
    }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
