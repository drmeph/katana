# Katana

Slice through your camera roll. Katana shows your photos and videos one at a time:

- **Swipe right** to keep, **swipe left** to archive, **double-tap** to favorite (syncs with Apple Photos)
- **Filters** for All, Screenshots and Videos, with **Undo**
- **Archive** tab: see how much space your rejects take up, tap any item to rescue it, then delete everything in one tap. Deleted items go to *Recently Deleted* in Photos for 30 days.
- Fully on-device: no network, no accounts, no limits.

## Run it on your iPhone

Requirements: a Mac with **Xcode 16 or newer**, an iPhone on **iOS 17+**, and a free Apple ID.

1. `git clone` this repo, then open `Katana.xcodeproj`.
2. In Xcode, select the **Katana** target → **Signing & Capabilities** → choose your Apple ID under **Team**
   (Xcode → Settings → Accounts to add one). If Xcode says the bundle ID is taken,
   change `dev.katana.photosorter` to something unique like `com.yourname.katana`.
3. Plug in your iPhone, unlock it, and tap **Trust** if asked.
4. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (it restarts).
5. Pick your iPhone in Xcode's device menu at the top and press **Run** (⌘R).
6. First launch only: **Settings → General → VPN & Device Management** → trust your developer profile.

With a free Apple ID, the app stops opening after 7 days. Press Run again to refresh it.

You can also try it in the iOS Simulator without signing. Drag some photos onto the simulator window to give it a library.
