import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var receiver: Receiver
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name = receiver.deviceName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: receiver.togglePower) {
                    Image(systemName: "power")
                        .foregroundStyle(receiver.isOn ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(receiver.status == nil)
            }

            if !receiver.routines.isEmpty {
                HStack(spacing: 6) {
                    ForEach(receiver.routines) { routine in
                        Button(routine.name) { receiver.run(routine) }
                            .help(routine.summary)
                    }
                }
                .controlSize(.small)
                .disabled(receiver.status == nil || receiver.runningRoutine != nil)
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
                Text(receiver.volumeText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
            }
            .disabled(!receiver.isOn)

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
