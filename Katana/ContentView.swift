import Photos
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch library.status {
            case .authorized, .limited:
                TabView {
                    SwipeView()
                        .tabItem { Label("Sort", systemImage: "rectangle.stack") }
                    ArchiveView()
                        .tabItem { Label("Archive", systemImage: "archivebox") }
                        .badge(library.archived.count)
                }
            case .notDetermined:
                WelcomeView()
            default:
                AccessDeniedView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refreshStatus() }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var library: PhotoLibrary

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "scissors")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Katana")
                .font(.largeTitle.bold())
            Text("Slice through your camera roll. Swipe right to keep, left to archive, double-tap to favorite. Then delete the archive in one go.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Label("Your photos never leave this iPhone.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await library.requestAccess() }
            } label: {
                Text("Allow Photo Access")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}

private struct AccessDeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Photo Access", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Katana needs full access to your photo library to sort and clean it up.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
