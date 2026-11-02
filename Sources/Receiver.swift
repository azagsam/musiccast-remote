import Foundation
import SwiftUI

struct InputChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let usesNetPlayback: Bool
}

struct Preset: Identifiable, Hashable {
    enum Source: Hashable { case net, tuner }

    let source: Source
    let number: Int
    let name: String

    var id: String { "\(source)-\(number)" }
}

@MainActor
final class Receiver: ObservableObject {
    private static let hostKey = "host"
    private static let defaultHost = "192.168.0.41"
    private static let pollInterval: UInt64 = 2_500_000_000
    /// How long a poll may not overwrite the slider after the user moves it.
    private static let volumeHold: TimeInterval = 1.5

    @Published var host: String
    @Published private(set) var status: ZoneStatus?
    @Published private(set) var inputs: [InputChoice] = []
    @Published private(set) var presets: [Preset] = []
    @Published private(set) var play: PlayInfo?
    @Published private(set) var error: String?
    @Published var volume: Double = 0

    private var client: Client
    private var pollTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var volumeHeldUntil = Date.distantPast
    private var catalogLoaded = false

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.hostKey) ?? Self.defaultHost
        host = saved
        client = Client(host: saved)
    }

    var isOn: Bool { status?.power == "on" }
    var maxVolume: Double { Double(status?.max_volume ?? 161) }
    var currentInput: InputChoice? { inputs.first { $0.id == status?.input } }
    var showsPlayback: Bool { currentInput?.usesNetPlayback ?? false }
    var isPlaying: Bool { play?.playback == "play" }

    var artworkURL: URL? {
        guard let path = play?.albumart_url, !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: client.baseURL)
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            }
        }
    }

    func connect() {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        host = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.hostKey)
        client = Client(host: trimmed)
        catalogLoaded = false
        status = nil
        play = nil
        inputs = []
        presets = []
        Task { await refresh() }
    }

    func refresh() async {
        let client = self.client
        do {
            if !catalogLoaded {
                try await loadCatalog()
            }
            let latest: ZoneStatus = try await client.get("main/getStatus")
            guard client.host == self.client.host else { return }
            status = latest
            if Date() >= volumeHeldUntil {
                volume = Double(latest.volume)
            }
            play = showsPlayback ? try await client.get("netusb/getPlayInfo") : nil
            error = nil
        } catch {
            guard client.host == self.client.host else { return }
            self.error = error.localizedDescription
        }
    }

    /// Inputs and presets come from the receiver, so other models work too.
    private func loadCatalog() async throws {
        let features: Features = try await client.get("system/getFeatures")
        let names: NameText = try await client.get("system/getNameText")
        let netPresets: NetPresets = try await client.get("netusb/getPresetInfo")
        // Models without a tuner reject this call.
        let tunerPresets: TunerPresets? = try? await client.get("tuner/getPresetInfo?band=common")

        let zoneInputs = features.zone.first { $0.id == "main" }?.input_list
        let nameByID = Dictionary(
            (names.input_list ?? []).map { ($0.id, $0.text) },
            uniquingKeysWith: { first, _ in first }
        )
        inputs = features.system.input_list
            .filter { zoneInputs?.contains($0.id) ?? true }
            .map {
                InputChoice(
                    id: $0.id,
                    name: nameByID[$0.id] ?? $0.id,
                    usesNetPlayback: $0.play_info_type == "netusb"
                )
            }

        let net = netPresets.preset_info.enumerated().compactMap { index, item -> Preset? in
            guard item.input != "unknown", !item.text.isEmpty else { return nil }
            return Preset(source: .net, number: index + 1, name: item.text)
        }
        let tuner = (tunerPresets?.preset_info ?? []).enumerated().compactMap { index, item -> Preset? in
            guard item.band != "unknown" else { return nil }
            return Preset(source: .tuner, number: index + 1, name: Self.frequencyName(item))
        }
        presets = net + tuner
        catalogLoaded = true
    }

    private static func frequencyName(_ item: TunerPresets.Item) -> String {
        if item.band == "fm" {
            return String(format: "FM %.1f MHz", Double(item.number) / 1000)
        }
        return "\(item.band.uppercased()) \(item.number) kHz"
    }

    func togglePower() {
        perform("main/setPower?power=\(isOn ? "standby" : "on")")
    }

    func toggleMute() {
        perform("main/setMute?enable=\(status?.mute == true ? "false" : "true")")
    }

    func select(input id: String) {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        perform("main/setInput?input=\(encoded)")
    }

    func recall(_ preset: Preset) {
        switch preset.source {
        case .net:
            perform("netusb/recallPreset?zone=main&num=\(preset.number)")
        case .tuner:
            perform("tuner/recallPreset?zone=main&band=common&num=\(preset.number)")
        }
    }

    func playback(_ command: String) {
        perform("netusb/setPlayback?playback=\(command)")
    }

    func togglePlayback() {
        // Live radio has nothing to resume, so it stops rather than pauses.
        let stopCommand = status?.input == "net_radio" ? "stop" : "pause"
        playback(isPlaying ? stopCommand : "play")
    }

    /// Coalesces slider movement so a drag doesn't flood the receiver.
    func setVolume(_ value: Double) {
        volume = value.rounded()
        volumeHeldUntil = Date().addingTimeInterval(Self.volumeHold)
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.client.send("main/setVolume?volume=\(Int(self.volume))")
                self.error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func nudgeVolume(by delta: Double) {
        setVolume(min(max(volume + delta, 0), maxVolume))
    }

    private func perform(_ path: String) {
        Task {
            do {
                try await client.send(path)
                error = nil
                // Input changes take a moment to appear in getStatus.
                try await Task.sleep(nanoseconds: 300_000_000)
                await refresh()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
