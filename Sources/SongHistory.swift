import Foundation

/// A song heard on net radio.
struct Song: Codable, Identifiable, Hashable {
    var id = UUID()
    let date: Date
    let station: String
    let artist: String?
    let title: String

    /// Net radio reports the song as "Artist - Title"; anything else is kept whole as the title.
    static func split(_ track: String) -> (artist: String?, title: String) {
        guard let dash = track.range(of: " - ") else { return (nil, track) }
        return (String(track[..<dash.lowerBound]), String(track[dash.upperBound...]))
    }

    var text: String {
        [artist.map { "\($0) - \(title)" } ?? title, station].joined(separator: " · ")
    }
}

/// Keeps the song history in Application Support, newest first.
struct SongHistory {
    private static let limit = 2000

    static let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Remote for MusicCast", isDirectory: true)
            .appendingPathComponent("song-history.json")
    }()

    static func load() -> [Song] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Song].self, from: data)) ?? []
    }

    static func save(_ songs: [Song]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(Array(songs.prefix(limit))) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
