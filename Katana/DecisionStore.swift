import Foundation

/// Remembers which items you've already reviewed so they don't come back,
/// and which ones are waiting in the archive. Stored on-device only.
final class DecisionStore {
    private let defaults = UserDefaults.standard
    private enum Key {
        static let kept = "katana.kept"
        static let archived = "katana.archived"
        static let freedBytes = "katana.freedBytes"
        static let deletedCount = "katana.deletedCount"
    }

    private(set) var kept: Set<String>
    private(set) var archived: Set<String>

    init() {
        kept = Set(defaults.stringArray(forKey: Key.kept) ?? [])
        archived = Set(defaults.stringArray(forKey: Key.archived) ?? [])
    }

    var freedBytes: Int64 {
        get { (defaults.object(forKey: Key.freedBytes) as? NSNumber)?.int64Value ?? 0 }
        set { defaults.set(NSNumber(value: newValue), forKey: Key.freedBytes) }
    }

    var deletedCount: Int {
        get { defaults.integer(forKey: Key.deletedCount) }
        set { defaults.set(newValue, forKey: Key.deletedCount) }
    }

    func isReviewed(_ id: String) -> Bool {
        kept.contains(id) || archived.contains(id)
    }

    func keep(_ id: String) {
        archived.remove(id)
        kept.insert(id)
        save()
    }

    func archive(_ id: String) {
        kept.remove(id)
        archived.insert(id)
        save()
    }

    func forget(_ id: String) {
        kept.remove(id)
        archived.remove(id)
        save()
    }

    func removeFromArchive(_ ids: [String]) {
        archived.subtract(ids)
        save()
    }

    func resetAll() {
        kept.removeAll()
        archived.removeAll()
        freedBytes = 0
        deletedCount = 0
        save()
    }

    private func save() {
        defaults.set(Array(kept), forKey: Key.kept)
        defaults.set(Array(archived), forKey: Key.archived)
    }
}
