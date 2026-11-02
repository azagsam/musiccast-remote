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
    @Published var radioQuery = ""
    @Published private(set) var radioResults: [Station] = []
    @Published private(set) var radioMessage: String?
    @Published private(set) var radioBusy = false
    @Published var showingSearch = false

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

        presets = try await fetchPresets()
        catalogLoaded = true
    }

    private func fetchPresets() async throws -> [Preset] {
        let netPresets: NetPresets = try await client.get("netusb/getPresetInfo")
        // Models without a tuner reject this call.
        let tunerPresets: TunerPresets? = try? await client.get("tuner/getPresetInfo?band=common")

        let net = netPresets.preset_info.enumerated().compactMap { index, item -> Preset? in
            guard item.input != "unknown", !item.text.isEmpty else { return nil }
            return Preset(source: .net, number: index + 1, name: item.text)
        }
        let tuner = (tunerPresets?.preset_info ?? []).enumerated().compactMap { index, item -> Preset? in
            guard item.band != "unknown" else { return nil }
            return Preset(source: .tuner, number: index + 1, name: Self.frequencyName(item))
        }
        return net + tuner
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

    func remove(_ preset: Preset) {
        let path: String
        switch preset.source {
        case .net: path = "netusb/clearPreset?num=\(preset.number)"
        case .tuner: path = "tuner/clearPreset?band=common&num=\(preset.number)"
        }
        changePresets(requiring: [preset], path: path)
    }

    /// The preset that `preset` would swap places with, in the same list.
    func neighbor(of preset: Preset, by offset: Int) -> Preset? {
        let list = presets.filter { $0.source == preset.source }
        guard let index = list.firstIndex(of: preset), list.indices.contains(index + offset) else { return nil }
        return list[index + offset]
    }

    func move(_ preset: Preset, by offset: Int) {
        guard let target = neighbor(of: preset, by: offset) else { return }
        let path: String
        switch preset.source {
        case .net: path = "netusb/movePreset?from=\(preset.number)&to=\(target.number)"
        case .tuner: path = "tuner/movePreset?band=common&from=\(preset.number)&to=\(target.number)"
        }
        changePresets(requiring: [preset, target], path: path)
    }

    /// Presets are addressed by slot, so a list changed elsewhere could hit the wrong station.
    private func changePresets(requiring expected: [Preset], path: String) {
        Task {
            do {
                let fresh = try await fetchPresets()
                guard expected.allSatisfy(fresh.contains) else {
                    presets = fresh
                    throw AppError("Presets changed on the receiver. Nothing was modified.")
                }
                try await client.send(path)
                presets = try await fetchPresets()
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
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

    func run(_ command: VoiceCommand) {
        Task {
            switch command {
            case .power(let on):
                perform("main/setPower?power=\(on ? "on" : "standby")")
            case .mute(let on):
                perform("main/setMute?enable=\(on ? "true" : "false")")
            case .setVolume(let value):
                await turnOn()
                setVolume(min(Double(value), maxVolume))
            case .changeVolume(let delta):
                await turnOn()
                nudgeVolume(by: Double(delta))
            case .play:
                playback("play")
            case .stop:
                playback(status?.input == "net_radio" ? "stop" : "pause")
            case .next:
                playback("next")
            case .previous:
                playback("previous")
            case .preset(let preset):
                await turnOn()
                recall(preset)
            case .input(let id):
                await turnOn()
                select(input: id)
            }
        }
    }

    private func turnOn() async {
        guard !isOn else { return }
        do {
            try await client.send("main/setPower?power=on")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func searchRadio() {
        let query = radioQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        runRadioTask(busy: "Searching…") {
            let found = try await RadioBrowser(client: self.client).search(query)
            self.radioResults = found
            return found.isEmpty ? "No stations found" : nil
        }
    }

    func playRadio(_ station: Station) {
        runRadioTask(busy: "Starting \(station.name)…") {
            try await self.start(station)
            return nil
        }
    }

    func saveRadio(_ station: Station) {
        runRadioTask(busy: "Saving \(station.name)…") {
            let presets = try await self.freshNetPresets()
            if Self.isSaved(station.name, in: presets) {
                return "\(station.name) is already saved"
            }
            let slot = try Self.firstEmptySlot(in: presets)
            try await self.start(station)
            try await self.waitUntilPlaying(station.name)
            return try await self.store(station.name, in: slot)
        }
    }

    /// storePreset takes no station, it saves whatever is playing.
    func saveCurrentStation() {
        guard status?.input == "net_radio", let name = play?.artist, !name.isEmpty else { return }
        runRadioTask(busy: "Saving…") {
            let presets = try await self.freshNetPresets()
            if Self.isSaved(name, in: presets) {
                return "Already saved"
            }
            let slot = try Self.firstEmptySlot(in: presets)
            return try await self.store(name, in: slot)
        }
    }

    private func start(_ station: Station) async throws {
        if status?.input != "net_radio" {
            try await client.send("main/setInput?input=net_radio")
        }
        try await RadioBrowser(client: client).play(station)
    }

    private func waitUntilPlaying(_ name: String) async throws {
        for _ in 0..<24 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let info: PlayInfo = try await client.get("netusb/getPlayInfo")
            if info.playback == "play", info.artist?.hasPrefix(name) == true { return }
        }
        throw AppError("\(name) didn't start playing, so it wasn't saved")
    }

    private func store(_ name: String, in slot: Int) async throws -> String {
        try await client.send("netusb/storePreset?num=\(slot)")
        let presets = try await freshNetPresets()
        guard Self.isSaved(name, in: presets) else {
            throw AppError("The receiver didn't save \(name)")
        }
        catalogLoaded = false
        await refresh()
        return "Saved to preset \(slot)"
    }

    private func freshNetPresets() async throws -> [NetPresets.Item] {
        let presets: NetPresets = try await client.get("netusb/getPresetInfo")
        return presets.preset_info
    }

    private static func isSaved(_ name: String, in presets: [NetPresets.Item]) -> Bool {
        presets.contains { $0.text.hasPrefix(name) }
    }

    /// Storing into a used slot would replace that preset.
    private static func firstEmptySlot(in presets: [NetPresets.Item]) throws -> Int {
        guard let index = presets.firstIndex(where: { $0.input == "unknown" }) else {
            throw AppError("All preset slots are full")
        }
        return index + 1
    }

    private func runRadioTask(busy: String, _ work: @escaping () async throws -> String?) {
        guard !radioBusy else { return }
        radioBusy = true
        radioMessage = busy
        Task {
            do {
                radioMessage = try await work()
            } catch {
                radioMessage = error.localizedDescription
            }
            radioBusy = false
        }
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
