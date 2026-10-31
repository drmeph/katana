import SwiftUI

@main
struct KatanaApp: App {
    @StateObject private var library = PhotoLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
        }
    }
}
