import Foundation
import SwiftUI

struct InputChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let usesNetPlayback: Bool

    enum Group: String, CaseIterable {
        case network = "Network", tuner = "Tuner", hdmi = "HDMI", other = "Other"
    }

    var group: Group {
        if id == "tuner" { return .tuner }
        if id.hasPrefix("hdmi") || id == "tv" { return .hdmi }
        if usesNetPlayback && id != "usb" { return .network }
        return .other
    }

    /// Net Radio and Tuner have presets to browse; other inputs are driven from their source.
    var hasPresets: Bool { id == "net_radio" || id == "tuner" }
}

struct Preset: Identifiable, Hashable {
    enum Source: Hashable { case net, tuner }

    let source: Source
    let number: Int
    let name: String

    var id: String { "\(source)-\(number)" }

    /// Net presets read "Station (City/Language)"; the parenthesised part is shown dimmed.
    var title: String { split.title }
    var detail: String? { split.detail }

    private var split: (title: String, detail: String?) {
        guard name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) else { return (name, nil) }
        return (String(name[..<open.lowerBound]), String(name[open.upperBound...].dropLast()))
    }
}

@MainActor
final class Receiver: ObservableObject {
    private static let hostKey = "host"
    private static let deviceIDKey = "deviceID"
    private static let recentKey = "recentInputs"
    private static let recentCount = 4
    private static let pollInterval: UInt64 = 2_500_000_000
    /// How long a poll may not overwrite the slider after the user moves it.
    private static let volumeHold: TimeInterval = 1.5

    @Published var host: String
    @Published private(set) var deviceName: String?
    @Published private(set) var status: ZoneStatus?
    @Published private(set) var inputs: [InputChoice] = []
    @Published private(set) var presets: [Preset] = []
    @Published private(set) var play: PlayInfo?
    /// The tuned frequency, named like tuner presets, while the input is Tuner.
    @Published private(set) var tunerStation: String?
    @Published private(set) var recentInputIDs: [String] = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    @Published private(set) var error: String?
    @Published var volume: Double = 0
    @Published var radioQuery = ""
    @Published private(set) var radioResults: [Station] = []
    @Published private(set) var radioMessage: String?
    @Published private(set) var radioBusy = false
    @Published var showingSearch = false
    @Published private(set) var discovered: [DiscoveredReceiver] = []
    @Published private(set) var discovering = false

    private var client: Client
    private var pollTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var volumeHeldUntil = Date.distantPast
    private var catalogLoaded = false

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.hostKey) ?? ""
        host = saved
        client = Client(host: saved)
    }

    var isOn: Bool { status?.power == "on" }
    var maxVolume: Double { Double(status?.max_volume ?? 161) }

    /// The volume as the receiver's display shows it: 0.5 dB per step, top step is 0.0 dB.
    var volumeText: String {
        String(format: "%.1f dB", (volume - maxVolume) * 0.5)
    }
    var currentInput: InputChoice? { inputs.first { $0.id == status?.input } }
    var showsPlayback: Bool { currentInput?.usesNetPlayback ?? false }
    var isPlaying: Bool { play?.playback == "play" }
    var isRadio: Bool { status?.input == "net_radio" }
    var isTuner: Bool { status?.input == "tuner" }

    var recentInputs: [InputChoice] {
        recentInputIDs.compactMap { id in inputs.first { $0.id == id } }
    }

    /// Presets for the current input, if it has any.
    var currentPresets: [Preset] {
        if isRadio { return presets.filter { $0.source == .net } }
        if isTuner { return presets.filter { $0.source == .tuner } }
        return []
    }

    /// The preset that is playing now, matched by station name or frequency.
    var currentPreset: Preset? {
        if isTuner {
            guard let tunerStation else { return nil }
            return currentPresets.first { $0.name == tunerStation }
        }
        guard isRadio, let station = play?.artist, !station.isEmpty else { return nil }
        return currentPresets.first { $0.name.hasPrefix(station) || station.hasPrefix($0.name) }
    }

    /// Previous or next preset, wrapping around, for the station buttons.
    func step(by offset: Int) {
        let list = currentPresets
        guard !list.isEmpty else { return }
        let index = currentPreset.flatMap(list.firstIndex(of:)) ?? (offset > 0 ? -1 : 0)
        recall(list[(index + offset + list.count) % list.count])
    }

    var artworkURL: URL? {
        guard let path = play?.albumart_url, !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: client.baseURL)
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.findOnLaunch()
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            }
        }
    }

    /// With no receiver saved, or the saved one gone (its IP may have changed), look for it.
    private func findOnLaunch() async {
        if !host.isEmpty {
            await refresh()
            guard error != nil else { return }
        }
        await discover()
        guard client.host == host, error != nil || host.isEmpty else { return }
        let savedID = UserDefaults.standard.string(forKey: Self.deviceIDKey)
        let match = host.isEmpty
            ? discovered.first
            : discovered.first { savedID != nil && $0.deviceID == savedID }
        if let match { connect(to: match) }
    }

    func discover() async {
        guard !discovering else { return }
        discovering = true
        discovered = await Discovery.find()
        discovering = false
    }

    func connect(to found: DiscoveredReceiver) {
        host = found.host
        connect()
    }

    func connect() {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // A blank address means "find one" rather than "connect to nothing".
        guard !trimmed.isEmpty else {
            Task {
                await discover()
                if let first = discovered.first { connect(to: first) }
            }
            return
        }
        host = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.hostKey)
        client = Client(host: trimmed)
        catalogLoaded = false
        deviceName = nil
        status = nil
        play = nil
        inputs = []
        presets = []
        Task { await refresh() }
    }

    func refresh() async {
        let client = self.client
        guard !client.host.isEmpty else {
            error = discovering ? nil : "No receiver found. Choose one from the receiver menu."
            return
        }
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
            if latest.input == "tuner" {
                let tuner: TunerPlayInfo = try await client.get("tuner/getPlayInfo")
                tunerStation = Self.tunerName(tuner)
            } else {
                tunerStation = nil
            }
            noteRecent(latest.input)
            error = nil
        } catch {
            guard client.host == self.client.host else { return }
            self.error = error.localizedDescription
        }
    }

    /// Inputs and presets come from the receiver, so other models work too.
    private func loadCatalog() async throws {
        let network: NetworkStatus = try await client.get("system/getNetworkStatus")
        deviceName = network.network_name
        if let info: DeviceInfo = try? await client.get("system/getDeviceInfo"), let id = info.device_id {
            UserDefaults.standard.set(id, forKey: Self.deviceIDKey)
        }
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
        frequencyName(band: item.band, frequency: item.number)
    }

    private static func frequencyName(band: String, frequency: Int) -> String {
        if band == "fm" {
            return String(format: "FM %.1f MHz", Double(frequency) / 1000)
        }
        return "\(band.uppercased()) \(frequency) kHz"
    }

    private static func tunerName(_ info: TunerPlayInfo) -> String? {
        switch info.band {
        case "fm": return info.fm.map { frequencyName(band: "fm", frequency: $0.freq) }
        case "am": return info.am.map { frequencyName(band: "am", frequency: $0.freq) }
        default: return nil
        }
    }

    private func noteRecent(_ id: String) {
        guard recentInputIDs.first != id else { return }
        recentInputIDs = Array(([id] + recentInputIDs.filter { $0 != id }).prefix(Self.recentCount))
        UserDefaults.standard.set(recentInputIDs, forKey: Self.recentKey)
    }

    func togglePower() {
        perform("main/setPower?power=\(isOn ? "standby" : "on")")
    }

    func toggleMute() {
        perform("main/setMute?enable=\(status?.mute == true ? "false" : "true")")
    }

    func select(input id: String) {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        noteRecent(id)
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
