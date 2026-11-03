import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var receiver: Receiver
    @State private var presetToRemove: Preset?
    @State private var editingHost = false
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                nowPlaying
                    .padding(.horizontal, 20)
                volume
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                inputSection
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                if receiver.currentInput?.hasPresets == true {
                    stationList
                } else {
                    externalSource
                }
            }
            .opacity(receiver.isOn ? 1 : 0.4)
            .disabled(!receiver.isOn)
            .animation(.easeInOut(duration: 0.2), value: receiver.isOn)

            messages
        }
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $receiver.showingSearch) {
            RadioSearchView().environmentObject(receiver)
        }
        .confirmationDialog(
            "Remove \(presetToRemove?.name ?? "this preset")?",
            isPresented: Binding(
                get: { presetToRemove != nil },
                set: { if !$0 { presetToRemove = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let preset = presetToRemove { receiver.remove(preset) }
            }
        } message: {
            Text("This clears the preset on the receiver.")
        }
        .onChange(of: receiver.status?.input) { _ in query = "" }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Button { editingHost = true } label: {
                    HStack(spacing: 6) {
                        Text(receiver.deviceName ?? "Yamaha Remote")
                            .font(.system(size: 20, weight: .bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Change receiver")
                .popover(isPresented: $editingHost, arrowEdge: .bottom) {
                    HostEditor { editingHost = false }.environmentObject(receiver)
                }

                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText)
                    if !receiver.host.isEmpty {
                        Text("·").foregroundStyle(.tertiary)
                        Text(receiver.host).monospacedDigit()
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            powerButton
        }
    }

    private var statusText: String {
        guard receiver.status != nil else { return receiver.discovering ? "Searching…" : "Not connected" }
        return receiver.isOn ? "Connected" : "Standby"
    }

    private var statusColor: Color {
        guard receiver.status != nil else { return .red }
        return receiver.isOn ? .green : .gray
    }

    private var powerButton: some View {
        Button(action: receiver.togglePower) {
            HStack(spacing: 6) {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .bold))
                Text(receiver.isOn ? "On" : "Off")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(receiver.isOn ? Color.green : Color.secondary)
            .padding(.leading, 11)
            .padding(.trailing, 14)
            .frame(height: 36)
            .background(Capsule().fill(receiver.isOn ? Color.green.opacity(0.15) : Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(receiver.isOn ? "Standby" : "Turn on")
        .disabled(receiver.status == nil)
    }

    // MARK: Now playing

    private var nowPlaying: some View {
        let info = NowPlaying(receiver)
        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                Artwork(url: receiver.artworkURL, label: info.artLabel, isTuner: receiver.isTuner)

                VStack(alignment: .leading, spacing: 2) {
                    if let status = info.status {
                        Text(status)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.4)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                    }
                    Text(info.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if let artist = info.artist {
                        Text(artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let station = info.station {
                        Text(station)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if receiver.isRadio {
                    saveButton
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if receiver.showsPlayback || receiver.isTuner {
                transport
            }
        }
        .padding(14)
        .background(Card(radius: 12))
    }

    private var saveButton: some View {
        let saved = receiver.currentPreset
        return Button {
            if let saved {
                presetToRemove = saved
            } else {
                receiver.saveCurrentStation()
            }
        } label: {
            Image(systemName: saved == nil ? "star" : "star.fill")
                .font(.system(size: 15))
                .foregroundStyle(saved == nil ? Color.secondary : Color.orange)
        }
        .buttonStyle(IconButtonStyle(size: 32, radius: 16))
        .help(saved == nil ? "Save Current" : "Remove from Presets")
        .disabled(receiver.radioBusy || (saved == nil && receiver.play?.artist?.isEmpty != false))
    }

    private var transport: some View {
        let stepsPresets = receiver.isRadio || receiver.isTuner
        return HStack(spacing: 22) {
            Button {
                stepsPresets ? receiver.step(by: -1) : receiver.playback("previous")
            } label: {
                Image(systemName: "backward.fill").font(.system(size: 17))
            }
            .buttonStyle(IconButtonStyle(size: 40, radius: 20))
            .help(stepsPresets ? "Previous preset" : "Previous")

            if !receiver.isTuner {
                Button(action: receiver.togglePlayback) {
                    Image(systemName: playIcon)
                        .font(.system(size: 17))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.primary))
                }
                .buttonStyle(PressScaleStyle())
                .help(receiver.isPlaying ? (receiver.isRadio ? "Stop" : "Pause") : "Play")
            }

            Button {
                stepsPresets ? receiver.step(by: 1) : receiver.playback("next")
            } label: {
                Image(systemName: "forward.fill").font(.system(size: 17))
            }
            .buttonStyle(IconButtonStyle(size: 40, radius: 20))
            .help(stepsPresets ? "Next preset" : "Next")
        }
        .frame(maxWidth: .infinity)
    }

    private var playIcon: String {
        guard receiver.isPlaying else { return "play.fill" }
        // Live radio has nothing to resume, so it stops rather than pauses.
        return receiver.isRadio ? "stop.fill" : "pause.fill"
    }

    // MARK: Volume

    private var isMuted: Bool { receiver.status?.mute == true }

    private var volume: some View {
        HStack(spacing: 10) {
            Button(action: receiver.toggleMute) {
                Image(systemName: muteIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(isMuted ? Color.red : Color.primary)
                    .frame(width: 20, alignment: .leading)
            }
            .buttonStyle(IconButtonStyle(size: 28, radius: 6))
            .help(isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(get: { receiver.volume }, set: { receiver.setVolume($0) }),
                in: 0...receiver.maxVolume
            )
            .tint(isMuted ? .gray : .accentColor)

            Text(isMuted ? "Muted" : "\(Int(receiver.volume))")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

            HStack(spacing: 0) {
                Button { receiver.nudgeVolume(by: -2) } label: { Image(systemName: "minus") }
                    .buttonStyle(SegmentStyle())
                    .help("Volume down")
                Rectangle().fill(Color.primary.opacity(0.14)).frame(width: 0.5)
                Button { receiver.nudgeVolume(by: 2) } label: { Image(systemName: "plus") }
                    .buttonStyle(SegmentStyle())
                    .help("Volume up")
            }
            .frame(height: 24)
            .background(Card(radius: 7))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private var muteIcon: String {
        if isMuted { return "speaker.slash.fill" }
        return receiver.volume > receiver.maxVolume / 2 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"
    }

    // MARK: Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            // Recent inputs always include the current one, so the menu needn't repeat it.
            HStack(spacing: 6) {
                ForEach(receiver.recentInputs) { input in
                    RecentChip(name: input.name, selected: input.id == receiver.status?.input) {
                        receiver.select(input: input.id)
                    }
                }
                Spacer(minLength: 8)
                allInputsMenu
            }
        }
    }

    private var allInputsMenu: some View {
        Menu {
            Picker("Input", selection: Binding(
                get: { receiver.status?.input ?? "" },
                set: { receiver.select(input: $0) }
            )) {
                ForEach(InputChoice.Group.allCases, id: \.self) { group in
                    let members = receiver.inputs.filter { $0.group == group }
                    if !members.isEmpty {
                        Section(group.rawValue) {
                            ForEach(members) { input in
                                Text(input.name).tag(input.id)
                            }
                        }
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text("All Inputs")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(receiver.inputs.isEmpty)
    }

    // MARK: Stations

    private var filteredPresets: [Preset] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return receiver.currentPresets }
        return receiver.currentPresets.filter { $0.name.lowercased().contains(needle) }
    }

    private var stationList: some View {
        let all = receiver.currentPresets
        let shown = filteredPresets
        let current = receiver.currentPreset
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField(receiver.isTuner ? "Search presets" : "Search stations", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Card(radius: 7))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !shown.isEmpty {
                        Text("Presets")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.3)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                    }
                    ForEach(shown) { preset in
                        StationRow(
                            preset: preset,
                            isCurrent: preset == current,
                            isPlaying: receiver.isTuner || receiver.isPlaying
                        ) {
                            receiver.recall(preset)
                        }
                        .contextMenu {
                            Button("Move Up") { receiver.move(preset, by: -1) }
                                .disabled(receiver.neighbor(of: preset, by: -1) == nil)
                            Button("Move Down") { receiver.move(preset, by: 1) }
                                .disabled(receiver.neighbor(of: preset, by: 1) == nil)
                            Divider()
                            Button("Remove…", role: .destructive) { presetToRemove = preset }
                        }
                    }
                    if shown.isEmpty {
                        Text(all.isEmpty ? "No presets yet" : "No presets match “\(query)”")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 180, maxHeight: .infinity)
            .background(Card(radius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)

            HStack {
                if receiver.isRadio {
                    Button("Find Stations…") { receiver.showingSearch = true }
                }
                Spacer()
                Text("\(all.count) \(all.count == 1 ? "preset" : "presets")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
    }

    private var externalSource: some View {
        VStack(spacing: 4) {
            Text(receiver.currentInput.map { "Playing from \($0.name)" } ?? "Not connected")
                .font(.system(size: 14, weight: .semibold))
            Text(receiver.currentInput == nil
                 ? "Check the receiver address above."
                 : "Browse and pick tracks on the source device. Volume and power stay here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var messages: some View {
        let lines = [
            receiver.showingSearch ? nil : receiver.radioMessage.map { ($0, Color.secondary) },
            receiver.error.map { ($0, Color.red) },
        ].compactMap { $0 }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.0) { text, color in
                    Text(text).foregroundStyle(color)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Now playing text

/// What the now-playing card shows for the current input.
private struct NowPlaying {
    /// Only set when something isn't playing; playback itself needs no label.
    var status: String?
    var title = ""
    var artist: String?
    var station: String?
    var artLabel = ""

    @MainActor
    init(_ receiver: Receiver) {
        guard receiver.status != nil else {
            status = "Offline"
            title = "Not connected"
            return
        }
        guard receiver.isOn else {
            status = "Standby"
            title = receiver.currentInput?.name ?? "Standby"
            artLabel = Self.initials(title)
            return
        }
        let play = receiver.play
        if receiver.isTuner {
            title = receiver.tunerStation ?? "Tuner"
            artist = "Live broadcast"
            station = "Tuner"
            artLabel = "FM"
        } else if receiver.isRadio {
            status = receiver.isPlaying ? nil : "Stopped"
            let stationName = play?.artist ?? ""
            // Net radio reports the song as "Artist - Title" and the station as the artist.
            let track = play?.track ?? ""
            if let dash = track.range(of: " - ") {
                artist = String(track[..<dash.lowerBound])
                title = String(track[dash.upperBound...])
            } else {
                title = track.isEmpty ? (stationName.isEmpty ? "Net Radio" : stationName) : track
            }
            station = stationName.isEmpty ? nil : stationName
            artLabel = Self.initials(stationName)
        } else if receiver.showsPlayback {
            status = receiver.isPlaying ? nil : "Paused"
            title = play?.track.flatMap { $0.isEmpty ? nil : $0 } ?? receiver.currentInput?.name ?? ""
            artist = play?.artist.flatMap { $0.isEmpty ? nil : $0 }
            station = play?.album.flatMap { $0.isEmpty ? nil : $0 } ?? receiver.currentInput?.name
            artLabel = Self.initials(receiver.currentInput?.name ?? "")
        } else {
            status = "Input"
            title = receiver.currentInput?.name ?? ""
            artLabel = Self.initials(title)
        }
    }

    private static func initials(_ text: String) -> String {
        let words = text.split(separator: " ").filter { $0.first?.isUppercase == true || $0.first?.isNumber == true }
        return String(words.prefix(2).compactMap(\.first))
    }
}

// MARK: - Pieces

private struct Card: View {
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }
}

private struct Artwork: View {
    let url: URL?
    let label: String
    let isTuner: Bool

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                isTuner ? Color(red: 0.23, green: 0.35, blue: 0.55) : Color(white: 0.11)
                Text(label)
                    .font(.system(size: 20, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
    }
}

private struct StationRow: View {
    let preset: Preset
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(preset.title)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                    if let detail = preset.detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(isCurrent ? Color.white.opacity(0.8) : Color.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isCurrent && isPlaying {
                    Equalizer()
                }
            }
            .foregroundStyle(isCurrent ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.accentColor : Color.primary.opacity(hovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Three bouncing bars marking the station that is on air.
private struct Equalizer: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3) { bar in
                    let period = 0.7 + Double(bar) * 0.18
                    let phase = (time + Double(bar) * 0.12) / period * 2 * .pi
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: 2, height: 11 * (0.675 - 0.325 * cos(phase)))
                }
            }
            .frame(height: 11, alignment: .bottom)
        }
    }
}

private struct RecentChip: View {
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct HostEditor: View {
    @EnvironmentObject private var receiver: Receiver
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Receivers on this network")
                    .font(.headline)
                Spacer()
                if receiver.discovering {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await receiver.discover() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Search again")
                }
            }

            if receiver.discovered.isEmpty {
                Text(receiver.discovering ? "Searching…" : "No receivers found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(receiver.discovered) { found in
                        Button { pick(found) } label: { row(found) }
                            .buttonStyle(.plain)
                    }
                }
            }

            Divider().padding(.vertical, 2)

            Text("Or enter an IP address")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                TextField("192.168.0.41", text: $receiver.host)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
                Button("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 280)
        .task { await receiver.discover() }
    }

    private func row(_ found: DiscoveredReceiver) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hifispeaker.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(found.name).lineLimit(1)
                Text([found.model, found.host].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if found.host == receiver.host && receiver.status != nil {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func pick(_ found: DiscoveredReceiver) {
        receiver.connect(to: found)
        done()
    }

    private func connect() {
        receiver.connect()
        done()
    }
}

/// A borderless icon button that shows a soft background on hover.
private struct IconButtonStyle: ButtonStyle {
    let size: CGFloat
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration, size: size, radius: radius)
    }

    private struct HoverLabel: View {
        let configuration: Configuration
        let size: CGFloat
        let radius: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: radius)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (hovering && isEnabled ? 0.06 : 0)))
                )
                .contentShape(RoundedRectangle(cornerRadius: radius))
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

private struct SegmentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 30, height: 24)
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : 0))
            .contentShape(Rectangle())
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct RadioSearchView: View {
    @EnvironmentObject private var receiver: Receiver
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search internet radio", text: $receiver.radioQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { receiver.searchRadio() }
                Button("Search", action: receiver.searchRadio)
                    .disabled(receiver.radioBusy)
            }

            List(receiver.radioResults) { station in
                HStack {
                    Text(station.name).lineLimit(1)
                    Spacer()
                    Button { receiver.playRadio(station) } label: { Image(systemName: "play.fill") }
                        .help("Play")
                    Button { receiver.saveRadio(station) } label: { Image(systemName: "plus") }
                        .help("Play and save to presets")
                }
                .buttonStyle(.borderless)
            }
            .listStyle(.bordered)
            .disabled(receiver.radioBusy)

            HStack {
                Text(receiver.radioMessage ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 400, height: 460)
    }
}
