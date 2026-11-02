import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var receiver: Receiver
    @EnvironmentObject private var voice: VoiceController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: voice.toggle) {
                    Image(systemName: voice.isListening ? "mic.fill" : "mic")
                        .foregroundStyle(voice.isListening ? Color.red : Color.primary)
                }
                .buttonStyle(.borderless)
                .disabled(receiver.status == nil)
                Button(action: receiver.togglePower) {
                    Image(systemName: "power")
                        .foregroundStyle(receiver.isOn ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(receiver.status == nil)
            }

            HStack {
                Button(action: receiver.toggleMute) {
                    Image(systemName: receiver.status?.mute == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                Slider(
                    value: Binding(get: { receiver.volume }, set: { receiver.setVolume($0) }),
                    in: 0...receiver.maxVolume
                )
                Text("\(Int(receiver.volume))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
            .disabled(!receiver.isOn)

            if let message = voice.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(receiver.presets) { preset in
                        Button { receiver.recall(preset) } label: {
                            Text(preset.name)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 180)
            .disabled(!receiver.isOn)

            Divider()

            HStack {
                Button("Open Window") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 280)
    }

    private var title: String {
        guard receiver.status != nil else { return "Not connected" }
        guard receiver.isOn else { return "Standby" }
        if let track = receiver.play?.track, !track.isEmpty { return track }
        return receiver.currentInput?.name ?? ""
    }
}
