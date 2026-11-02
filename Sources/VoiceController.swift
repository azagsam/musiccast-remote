import AVFoundation
import Foundation
import Speech

/// Push-to-talk: listens until the speaker pauses, then runs one command.
@MainActor
final class VoiceController: ObservableObject {
    /// A mishearing like "volume 140" shouldn't be able to reach the top of the range.
    private static let maxVolume = 100
    private static let silentLevel: Float = 0.001
    /// kAFAssistantErrorDomain code for "no speech detected", which isn't a fault.
    private static let noSpeechCode = 1110
    private static let initialTimeout: UInt64 = 6_000_000_000
    private static let silenceTimeout: UInt64 = 1_200_000_000

    @Published private(set) var isListening = false
    @Published private(set) var message: String?

    private let receiver: Receiver
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var transcript = ""
    private var meter = LevelMeter()

    init(receiver: Receiver) {
        self.receiver = receiver
    }

    func toggle() {
        if isListening {
            finish()
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        guard await Self.requestPermissions() else {
            message = "Allow Microphone and Speech Recognition in System Settings → Privacy & Security"
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            message = "Speech recognition isn't available right now"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.contextualStrings = receiver.presets.map { $0.name.components(separatedBy: " (")[0] }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            message = "No microphone found"
            return
        }
        let meter = LevelMeter()
        self.meter = meter
        Self.installTap(on: input, format: format, feeding: request, meter: meter)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            message = error.localizedDescription
            return
        }

        self.request = request
        transcript = ""
        isListening = true
        message = "Listening…"
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self))
        scheduleTimeout(Self.initialTimeout)
    }

    private func heard(_ text: String?, isFinal: Bool, failure: String?) {
        guard isListening else { return }
        if let failure, transcript.isEmpty, text?.isEmpty != false {
            stopListening()
            message = failure
            return
        }
        if let text, !text.isEmpty {
            transcript = text
            message = "“\(text)”"
            scheduleTimeout(Self.silenceTimeout)
        }
        if isFinal { finish() }
    }

    private func scheduleTimeout(_ delay: UInt64) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        guard isListening else { return }
        stopListening()
        run(transcript)
    }

    private func stopListening() {
        isListening = false
        timeout?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func run(_ text: String) {
        guard !text.isEmpty else {
            let level = String(format: "%.3f", meter.peak)
            message = meter.peak < Self.silentLevel
                ? "The microphone is delivering silence (level \(level)). Check its permission and input device."
                : "Didn't hear any words (mic level \(level))"
            return
        }
        guard let command = VoiceCommand.parse(text, presets: receiver.presets, inputs: receiver.inputs) else {
            message = "Didn't understand “\(text)”"
            return
        }
        if case .setVolume(let value) = command, value > Self.maxVolume {
            message = "Voice volume is limited to \(Self.maxVolume)"
            return
        }
        message = "“\(text)”"
        receiver.run(command)
    }

    // These run on audio and speech queues, so they must not inherit main actor isolation.

    private nonisolated static func describe(_ error: Error) -> String? {
        let error = error as NSError
        if error.code == noSpeechCode { return nil }
        return "Speech recognition failed: \(error.localizedDescription) (\(error.domain) \(error.code))"
    }

    private nonisolated static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    private nonisolated static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        feeding request: SFSpeechAudioBufferRecognitionRequest,
        meter: LevelMeter
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            meter.record(buffer)
        }
    }

    private nonisolated static func resultHandler(
        for controller: VoiceController
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak controller] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true || error != nil
            let failure = error.flatMap(describe)
            Task { @MainActor in
                controller?.heard(text, isFinal: isFinal, failure: failure)
            }
        }
    }
}

/// Loudest sample seen, which tells a muted microphone apart from unrecognized speech.
private final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var loudest: Float = 0

    var peak: Float {
        lock.lock()
        defer { lock.unlock() }
        return loudest
    }

    func record(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        var maximum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            maximum = max(maximum, abs(samples[index]))
        }
        lock.lock()
        loudest = max(loudest, maximum)
        lock.unlock()
    }
}
