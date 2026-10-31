import Photos
import SwiftUI

/// Loads a photo or video thumbnail from the library and fills its frame.
struct AssetImage: View {
    let asset: PHAsset
    var targetSize = CGSize(width: 1200, height: 1200)

    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: asset.localIdentifier) {
                image = await load()
            }
    }

    private func load() async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // single callback
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true // fetch from iCloud if needed

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
