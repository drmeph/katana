import Photos
import SwiftUI

struct SwipeView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Filter", selection: $library.filter) {
                    ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                ZStack {
                    if library.queue.isEmpty {
                        ContentUnavailableView(
                            "All Caught Up",
                            systemImage: "checkmark.seal",
                            description: Text("Nothing left to review here. Check the Archive tab to free up space.")
                        )
                    }
                    let visible = Array(library.queue.prefix(3).enumerated())
                    ForEach(visible.reversed(), id: \.element.localIdentifier) { index, asset in
                        SwipeCard(
                            asset: asset,
                            onDecision: { decision in
                                withAnimation(.spring) { library.decide(decision, on: asset) }
                            },
                            onFavorite: {
                                Task { await library.toggleFavorite(asset) }
                            }
                        )
                        .scaleEffect(1 - CGFloat(index) * 0.04)
                        .offset(y: CGFloat(index) * -14)
                        .allowsHitTesting(index == 0)
                        .transition(.opacity)
                    }
                }
                .frame(maxHeight: .infinity)

                controls
            }
            .padding()
            .navigationTitle("Katana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if library.freedBytes > 0 {
                        Label(library.freedBytes.formattedBytes + " freed", systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.green)
                            .fixedSize()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Text("\(library.reviewedCount) reviewed · \(library.deletedCount) deleted")
                        Button("Reload Library", systemImage: "arrow.clockwise") { library.reload() }
                        Button("Reset Progress", systemImage: "arrow.counterclockwise", role: .destructive) {
                            confirmReset = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Reset progress?",
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) { library.resetProgress() }
            } message: {
                Text("Every photo will show up for review again and the archive will be emptied. Nothing is deleted from your library.")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            RoundButton(systemImage: "xmark", color: .red, size: 64) {
                if let top = library.queue.first {
                    withAnimation(.spring) { library.decide(.archive, on: top) }
                }
            }
            .disabled(library.queue.isEmpty)
            .accessibilityLabel("Archive")

            RoundButton(systemImage: "arrow.uturn.backward", color: .secondary, size: 48) {
                withAnimation(.spring) { library.undo() }
            }
            .disabled(!library.canUndo)
            .opacity(library.canUndo ? 1 : 0.4)
            .accessibilityLabel("Undo")

            RoundButton(systemImage: "checkmark", color: .green, size: 64) {
                if let top = library.queue.first {
                    withAnimation(.spring) { library.decide(.keep, on: top) }
                }
            }
            .disabled(library.queue.isEmpty)
            .accessibilityLabel("Keep")
        }
    }
}

private struct RoundButton: View {
    let systemImage: String
    let color: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}

struct SwipeCard: View {
    let asset: PHAsset
    let onDecision: (PhotoLibrary.Decision) -> Void
    let onFavorite: () -> Void

    @State private var offset: CGSize = .zero
    @State private var heartScale: CGFloat = 0
    @State private var heartFilled = true
    @State private var decided = false

    private let threshold: CGFloat = 110

    var body: some View {
        AssetImage(asset: asset)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .topLeading) {
                stamp("KEEP", color: .green)
                    .rotationEffect(.degrees(-12))
                    .opacity(Double(max(0, offset.width / threshold)))
                    .padding(24)
            }
            .overlay(alignment: .topTrailing) {
                stamp("ARCHIVE", color: .red)
                    .rotationEffect(.degrees(12))
                    .opacity(Double(max(0, -offset.width / threshold)))
                    .padding(24)
            }
            .overlay(alignment: .bottom) { infoBar }
            .overlay {
                Image(systemName: heartFilled ? "heart.fill" : "heart.slash.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.white)
                    .shadow(radius: 10)
                    .scaleEffect(heartScale)
                    .opacity(heartScale > 0 ? 1 : 0)
            }
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            .rotationEffect(.degrees(Double(offset.width / 22)))
            .offset(offset)
            .onTapGesture(count: 2) {
                heartFilled = !asset.isFavorite
                onFavorite()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heartScale = 1 }
                withAnimation(.easeOut(duration: 0.3).delay(0.6)) { heartScale = 0 }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !decided else { return }
                        offset = value.translation
                    }
                    .onEnded { value in
                        guard !decided else { return }
                        let dx = value.translation.width
                        let predicted = value.predictedEndTranslation.width
                        if dx > threshold || predicted > threshold * 3 {
                            flyOut(.keep, direction: 1, dy: value.translation.height)
                        } else if dx < -threshold || predicted < -threshold * 3 {
                            flyOut(.archive, direction: -1, dy: value.translation.height)
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = .zero }
                        }
                    }
            )
            .sensoryFeedback(.selection, trigger: decided)
    }

    private func flyOut(_ decision: PhotoLibrary.Decision, direction: CGFloat, dy: CGFloat) {
        decided = true
        withAnimation(.easeOut(duration: 0.22)) {
            offset = CGSize(width: direction * 700, height: dy * 1.5)
        } completion: {
            onDecision(decision)
        }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.title.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var infoBar: some View {
        HStack(spacing: 8) {
            if let date = asset.creationDate {
                Text(date, format: .dateTime.day().month(.abbreviated).year())
            }
            if asset.mediaType == .video {
                Label(duration, systemImage: "play.fill")
            }
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                Image(systemName: "camera.viewfinder")
            }
            Spacer()
            if asset.isFavorite {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(
            UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
        )
    }

    private var duration: String {
        let total = Int(asset.duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
