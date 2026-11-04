import Foundation

/// A named set of target settings, applied in order: power on, source, then volume.
struct Routine: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// The input to select, such as "net_radio" or "tuner".
    var input: String?
    /// A preset on that input, by name, so reordering presets doesn't break the routine.
    var preset: String?
    var decibels: Double?

    var summary: String {
        var parts: [String] = []
        if let preset { parts.append(preset) } else if let input { parts.append(input) }
        if let decibels { parts.append(String(format: "%.1f dB", decibels)) }
        return parts.isEmpty ? "Turn on" : parts.joined(separator: " · ")
    }
}

/// Keeps routines in Application Support.
enum RoutineStore {
    static let url = SongHistory.url.deletingLastPathComponent().appendingPathComponent("routines.json")

    static func load() -> [Routine] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Routine].self, from: data)) ?? []
    }

    static func save(_ routines: [Routine]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(routines) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
