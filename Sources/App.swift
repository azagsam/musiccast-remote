import Foundation
import SwiftUI

struct YamahaRemoteApp: App {
    @StateObject private var receiver = Receiver()

    var body: some Scene {
        WindowGroup("Yamaha Remote") {
            ContentView().environmentObject(receiver)
        }
        .windowResizability(.contentSize)
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

    /// Prints what the app would show, using read-only requests.
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
    }
}
