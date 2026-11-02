import Foundation
import SwiftUI

struct YamahaRemoteApp: App {
    @StateObject private var receiver: Receiver
    @StateObject private var voice: VoiceController

    init() {
        // Started here so the menu bar stays current with the window closed.
        let receiver = Receiver()
        receiver.start()
        _receiver = StateObject(wrappedValue: receiver)
        _voice = StateObject(wrappedValue: VoiceController(receiver: receiver))
    }

    var body: some Scene {
        Window("Yamaha Remote", id: "main") {
            ContentView()
                .environmentObject(receiver)
                .environmentObject(voice)
        }
        .windowResizability(.contentSize)
        .commands { ReceiverCommands(receiver: receiver, voice: voice) }

        MenuBarExtra("Yamaha Remote", systemImage: "hifispeaker.fill") {
            MenuBarView()
                .environmentObject(receiver)
                .environmentObject(voice)
        }
        .menuBarExtraStyle(.window)
    }
}

@main
enum Entry {
    static func main() {
        guard CommandLine.arguments.contains("--check") else {
            YamahaRemoteApp.main()
            return
        }
        Task { @MainActor in
            await check()
            exit(0)
        }
        dispatchMain()
    }

    /// Prints what the app would show, without changing playback or presets.
    @MainActor
    private static func check() async {
        let receiver = Receiver()
        await receiver.refresh()
        print("error:", receiver.error ?? "none")
        print("status:", receiver.status.map { "\($0.power) vol=\($0.volume) input=\($0.input)" } ?? "none")
        print("track:", receiver.play?.track ?? "none")
        print("artwork:", receiver.artworkURL?.absoluteString ?? "none")
        print("inputs:", receiver.inputs.map(\.name))
        print("presets:", receiver.presets.map { "\($0.number) \($0.name)" })

        let phrases = [
            "turn on", "turn it off", "turn on the radio", "standby", "mute", "unmute",
            "volume 40", "set the volume to 35", "volume forty", "volume up", "turn the volume down",
            "louder", "quieter", "volume 140", "next", "stop", "play",
            "play Val 202", "play val 2 0 2", "play bal 202", "turn on Val 202", "put on radio student",
            "play radio študent", "listen to KEXP", "play FIP", "play FIP pop", "play NTS radio",
            "play radio", "switch to bluetooth", "switch to spotify", "play phono",
            "what's the weather", "play something nice", "good morning"
        ]
        for phrase in phrases {
            let command = VoiceCommand.parse(phrase, presets: receiver.presets, inputs: receiver.inputs)
            print("voice '\(phrase)':", command.map { "\($0)" } ?? "nil")
        }

        // Navigates the receiver's menu but doesn't affect playback.
        for query in ["jazz", "radio študent", "zzqxv no such station"] {
            do {
                let found = try await RadioBrowser(client: Client(host: receiver.host)).search(query)
                print("search '\(query)':", found.count, found.prefix(4).map { "\($0.index):\($0.name)" })
            } catch {
                print("search '\(query)' failed:", error.localizedDescription)
            }
        }
    }
}
