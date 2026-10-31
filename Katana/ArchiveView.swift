import Photos
import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @State private var archiveBytes: Int64 = 0
    @State private var isDeleting = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if library.archived.isEmpty {
                    ContentUnavailableView(
                        "Archive Is Empty",
                        systemImage: "archivebox",
                        description: Text("Swipe left on anything you don't need. It lands here until you delete it.")
                    )
                } else {
                    ScrollView {
                        Text("Tap an item to keep it instead.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(library.archived, id: \.localIdentifier) { asset in
                                Button {
                                    withAnimation { library.restore(asset) }
                                } label: {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay { AssetImage(asset: asset, targetSize: CGSize(width: 300, height: 300)) }
                                        .clipped()
                                        .overlay(alignment: .bottomTrailing) {
                                            if asset.mediaType == .video {
                                                Image(systemName: "play.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.white)
                                                    .shadow(radius: 2)
                                                    .padding(6)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 96)
                    }
                }
            }
            .navigationTitle("Archive")
            .toolbar {
                if !library.archived.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Keep All") {
                            withAnimation { library.restoreAll() }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !library.archived.isEmpty {
                    Button {
                        isDeleting = true
                        Task {
                            await library.deleteArchived()
                            isDeleting = false
                        }
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "trash.fill")
                            }
                            Text(deleteTitle)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(isDeleting)
                    .padding()
                    .background(.bar)
                }
            }
            .task(id: library.archived.count) {
                archiveBytes = await PhotoLibrary.totalSize(of: library.archived)
            }
        }
    }

    private var deleteTitle: String {
        let count = library.archived.count
        let items = count == 1 ? "1 item" : "\(count) items"
        return archiveBytes > 0 ? "Delete \(items) · \(archiveBytes.formattedBytes)" : "Delete \(items)"
    }
}
