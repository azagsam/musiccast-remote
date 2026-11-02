import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var receiver: Receiver

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            nowPlaying
            volume
            inputPicker
            presets
            if let error = receiver.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 340, height: 560, alignment: .top)
        .task { receiver.start() }
    }

    private var header: some View {
        HStack {
            TextField("Receiver IP", text: $receiver.host)
                .textFieldStyle(.roundedBorder)
                .onSubmit { receiver.connect() }
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
        }
        .listStyle(.bordered)
        .disabled(!receiver.isOn)
    }
}
