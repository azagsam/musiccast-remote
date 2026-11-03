import Foundation
import SwiftUI

struct YamahaRemoteApp: App {
    @StateObject private var receiver: Receiver

    init() {
        // Started here so the menu bar stays current with the window closed.
        let receiver = Receiver()
        receiver.start()
        _receiver = StateObject(wrappedValue: receiver)
    }

    var body: some Scene {
        Window("Yamaha Remote", id: "main") {
            ContentView().environmentObject(receiver)
        }
        .defaultSize(width: 420, height: 760)
        .windowResizability(.contentMinSize)
        .commands { ReceiverCommands(receiver: receiver) }

        MenuBarExtra("Yamaha Remote", systemImage: "hifispeaker.fill") {
            MenuBarView().environmentObject(receiver)
        }
        .menuBarExtraStyle(.window)
    }
}

@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.contains("--check") || arguments.contains("--discover") else {
            YamahaRemoteApp.main()
            return
        }
        Task { @MainActor in
            if arguments.contains("--discover") {
                for found in await Discovery.find() {
                    print(found.host, found.name, found.model ?? "", found.deviceID ?? "")
                }
            } else {
                await check()
            }
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
        print("name:", receiver.deviceName ?? "none")
        print("status:", receiver.status.map { "\($0.power) vol=\($0.volume) input=\($0.input)" } ?? "none")
        print("track:", receiver.play?.track ?? "none")
        print("artwork:", receiver.artworkURL?.absoluteString ?? "none")
        print("inputs:", receiver.inputs.map(\.name))
        print("presets:", receiver.presets.map { "\($0.number) \($0.name)" })

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
