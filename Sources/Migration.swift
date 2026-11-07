import Foundation

/// Carries settings and data over from when the app was called "Yamaha Remote".
enum Migration {
    private static let oldDefaultsDomain = "local.pyamaha.YamahaRemote"
    private static let oldFolderName = "Yamaha Remote"
    private static let doneKey = "migratedFromYamahaRemote"

    /// Runs once, before anything reads user defaults or the data folder.
    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        if let old = defaults.persistentDomain(forName: oldDefaultsDomain) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        let fileManager = FileManager.default
        let newFolder = SongHistory.url.deletingLastPathComponent()
        let oldFolder = newFolder.deletingLastPathComponent().appendingPathComponent(oldFolderName, isDirectory: true)
        if fileManager.fileExists(atPath: oldFolder.path), !fileManager.fileExists(atPath: newFolder.path) {
            try? fileManager.copyItem(at: oldFolder, to: newFolder)
        }

        defaults.set(true, forKey: doneKey)
    }
}
