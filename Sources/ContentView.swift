import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var receiver: Receiver
    @EnvironmentObject private var voice: VoiceController
    @State private var presetToRemove: Preset?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            nowPlaying
            volume
            inputPicker
            presets
            radioActions
            if let message = voice.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let message = receiver.radioMessage, !receiver.showingSearch {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = receiver.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 340, height: 650, alignment: .top)
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
    }

    private var header: some View {
        HStack {
            TextField("Receiver IP", text: $receiver.host)
                .textFieldStyle(.roundedBorder)
                .onSubmit { receiver.connect() }
            Button(action: voice.toggle) {
                Image(systemName: voice.isListening ? "mic.fill" : "mic")
                    .foregroundStyle(voice.isListening ? Color.red : Color.primary)
            }
            .help("Voice command")
            .disabled(receiver.status == nil)
            Button(action: receiver.togglePower) {
                Image(systemName: "power")
                    .foregroundStyle(receiver.isOn ? Color.green : Color.secondary)
            }
            .help(receiver.isOn ? "Standby" : "Turn on")
            .disabled(receiver.status == nil)
        }
    }

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            AsyncImage(url: receiver.artworkURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "hifispeaker")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                if let artist = receiver.play?.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if receiver.showsPlayback {
                    transport
                }
            }
        }
        .frame(height: 76)
        .disabled(!receiver.isOn)
    }

    private var title: String {
        guard receiver.status != nil else { return "Not connected" }
        guard receiver.isOn else { return "Standby" }
        if let track = receiver.play?.track, !track.isEmpty { return track }
        return receiver.currentInput?.name ?? ""
    }

    private var transport: some View {
        HStack(spacing: 14) {
            Button { receiver.playback("previous") } label: { Image(systemName: "backward.fill") }
            Button(action: receiver.togglePlayback) {
                Image(systemName: receiver.isPlaying ? "stop.fill" : "play.fill")
            }
            Button { receiver.playback("next") } label: { Image(systemName: "forward.fill") }
        }
        .buttonStyle(.borderless)
    }

    private var volume: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Volume")
                Spacer()
                Text("\(Int(receiver.volume))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button { receiver.toggleMute() } label: {
                    Image(systemName: receiver.status?.mute == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                Slider(
                    value: Binding(get: { receiver.volume }, set: { receiver.setVolume($0) }),
                    in: 0...receiver.maxVolume
                )
                Button { receiver.nudgeVolume(by: -2) } label: { Image(systemName: "minus") }
                Button { receiver.nudgeVolume(by: 2) } label: { Image(systemName: "plus") }
            }
        }
        .disabled(!receiver.isOn)
    }

    private var inputPicker: some View {
        Picker("Input", selection: Binding(
            get: { receiver.status?.input ?? "" },
            set: { receiver.select(input: $0) }
        )) {
            ForEach(receiver.inputs) { input in
                Text(input.name).tag(input.id)
            }
        }
        .disabled(!receiver.isOn || receiver.inputs.isEmpty)
    }

    private var presets: some View {
        List(receiver.presets) { preset in
            Button { receiver.recall(preset) } label: {
                Text(preset.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Move Up") { receiver.move(preset, by: -1) }
                    .disabled(receiver.neighbor(of: preset, by: -1) == nil)
                Button("Move Down") { receiver.move(preset, by: 1) }
                    .disabled(receiver.neighbor(of: preset, by: 1) == nil)
                Divider()
                Button("Remove…", role: .destructive) { presetToRemove = preset }
            }
        }
        .listStyle(.bordered)
        .disabled(!receiver.isOn)
    }

    private var radioActions: some View {
        HStack {
            Button("Find Stations…") { receiver.showingSearch = true }
            Spacer()
            Button("Save Current", action: receiver.saveCurrentStation)
                .disabled(receiver.status?.input != "net_radio" || receiver.radioBusy)
        }
        .disabled(!receiver.isOn)
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
