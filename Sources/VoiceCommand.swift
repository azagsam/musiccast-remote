import Foundation

/// Turns a spoken phrase into a receiver action. Anything unclear parses to nil,
/// because doing nothing is better than acting on a mishearing.
enum VoiceCommand: Equatable {
    case power(Bool)
    case mute(Bool)
    case setVolume(Int)
    case changeVolume(Int)
    case play
    case stop
    case next
    case previous
    case preset(Preset)
    case input(String)

    private static let volumeStep = 6
    private static let maxDistance = 0.34
    private static let fillers: Set<String> = ["it", "the", "radio", "receiver", "amp", "amplifier", "yamaha", "please"]
    private static let targetPrefixes = ["play", "put on", "listen to", "switch to", "change to", "go to", "tune to", "turn on"]

    static func parse(_ text: String, presets: [Preset], inputs: [InputChoice]) -> VoiceCommand? {
        let phrase = fold(text)
        guard !phrase.isEmpty else { return nil }

        if let power = parsePower(phrase) { return .power(power) }
        if contains(phrase, "unmute") || contains(phrase, "un mute") { return .mute(false) }
        if contains(phrase, "mute") { return .mute(true) }
        if let volume = parseVolume(phrase) { return volume }

        switch phrase {
        case "play", "resume": return .play
        case "stop", "pause": return .stop
        case "next", "skip", "next track", "next song": return .next
        case "previous", "back", "go back", "previous track", "previous song": return .previous
        default: break
        }

        let target = stripPrefix(phrase)
        if let input = inputs.first(where: { fold($0.name) == target || fold($0.id) == target }) {
            return .input(input.id)
        }
        return bestPreset(for: target, in: presets).map(VoiceCommand.preset)
    }

    private static func parsePower(_ phrase: String) -> Bool? {
        for off in ["turn off", "turn it off", "switch off", "power off", "shut down", "standby"]
        where contains(phrase, off) {
            return false
        }
        for on in ["turn on", "turn it on", "switch on", "power on", "wake up"] where contains(phrase, on) {
            let rest = phrase.replacingOccurrences(of: on, with: "").split(separator: " ").map(String.init)
            // "turn on val 202" names a station, not the receiver.
            if rest.allSatisfy(fillers.contains) { return true }
        }
        return nil
    }

    private static func parseVolume(_ phrase: String) -> VoiceCommand? {
        let words = phrase.split(separator: " ").map(String.init)
        if words.contains("louder") { return .changeVolume(volumeStep) }
        if words.contains("quieter") || words.contains("softer") { return .changeVolume(-volumeStep) }
        guard let keyword = words.firstIndex(of: "volume") else { return nil }

        let afterKeyword = words[(keyword + 1)...].filter { $0 != "to" && $0 != "at" }
        if let digits = afterKeyword.compactMap({ Int($0) }).first { return .setVolume(digits) }
        if words.contains("up") { return .changeVolume(volumeStep) }
        if words.contains("down") { return .changeVolume(-volumeStep) }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .spellOut
        return formatter.number(from: afterKeyword.joined(separator: " ")).map { .setVolume($0.intValue) }
    }

    private static func stripPrefix(_ phrase: String) -> String {
        for prefix in targetPrefixes where phrase.hasPrefix(prefix + " ") {
            return String(phrase.dropFirst(prefix.count + 1))
        }
        return phrase
    }

    /// Returns a preset only when one is clearly closest, so "radio" picks nothing.
    private static func bestPreset(for target: String, in presets: [Preset]) -> Preset? {
        let query = target.replacingOccurrences(of: " ", with: "")
        guard query.count >= 3 else { return nil }

        let scored = presets
            .map { (preset: $0, score: score(query, against: stationKey($0))) }
            .sorted { $0.score < $1.score }
        guard let best = scored.first, best.score <= maxDistance else { return nil }
        if scored.count > 1, scored[1].score - best.score < 0.001 { return nil }
        return best.preset
    }

    private static func stationKey(_ preset: Preset) -> String {
        let name = preset.name.components(separatedBy: " (")[0]
        return fold(name).replacingOccurrences(of: " ", with: "")
    }

    private static func score(_ query: String, against key: String) -> Double {
        if query == key { return 0 }
        if key.contains(query) { return 0.1 }
        let distance = levenshtein(Array(query), Array(key))
        return Double(distance) / Double(max(query.count, key.count))
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var row = Array(0...b.count)
        for i in 0..<a.count {
            var previous = row[0]
            row[0] = i + 1
            for j in 0..<b.count {
                let current = row[j + 1]
                row[j + 1] = min(current + 1, row[j] + 1, previous + (a[i] == b[j] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }

    private static func contains(_ phrase: String, _ words: String) -> Bool {
        " \(phrase) ".contains(" \(words) ")
    }

    private static func fold(_ text: String) -> String {
        let plain = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(plain).split(separator: " ").joined(separator: " ")
    }
}
