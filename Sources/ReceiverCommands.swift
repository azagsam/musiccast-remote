import SwiftUI

struct ReceiverCommands: Commands {
    @ObservedObject var receiver: Receiver
    @ObservedObject var voice: VoiceController
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Receiver") {
            Button(voice.isListening ? "Stop Listening" : "Voice Command", action: voice.toggle)
                .keyboardShortcut("l", modifiers: .command)
                .disabled(receiver.status == nil)

            Divider()

            Button(receiver.isOn ? "Standby" : "Turn On", action: receiver.togglePower)
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(receiver.status == nil)

            Divider()

            Group {
                Button("Volume Up") { receiver.nudgeVolume(by: 2) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Volume Down") { receiver.nudgeVolume(by: -2) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Button(receiver.status?.mute == true ? "Unmute" : "Mute", action: receiver.toggleMute)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            .disabled(!receiver.isOn)

            Divider()

            Group {
                Button(receiver.isPlaying ? "Stop" : "Play", action: receiver.togglePlayback)
                    .keyboardShortcut("p", modifiers: .command)
                Button("Previous") { receiver.playback("previous") }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Next") { receiver.playback("next") }
                    .keyboardShortcut("]", modifiers: .command)
            }
            .disabled(!receiver.isOn || !receiver.showsPlayback)

            Divider()

            Button("Find Stations…") {
                openWindow(id: "main")
                receiver.showingSearch = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!receiver.isOn)
        }
    }
}
