//
//  SearchVoice.swift
//  Sunny
//
//  Ask by voice (block 27): the words appear in the field as you speak and,
//  about 1.6 s after you stop, Sunny asks on its own (Nik, Oct 28). Tap the
//  words to edit them as text; × stops. A refused microphone shows a glass
//  sheet over the field (Open Settings or Not now); typing still works.
//  Read aloud uses the iPhone's own voice.
//

import AVFoundation
import Observation
import Speech
import UIKit

@MainActor
@Observable
final class SXVoice {
    /// What has been heard so far.
    private(set) var words = ""
    private(set) var on = false
    /// Quiet for a moment: it asks on its own unless the words are tapped.
    private(set) var ending = false
    /// The microphone or speech recognition is turned off for Sunny.
    var denied = false

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var quiet: Task<Void, Never>?
    private var onAsk: ((String) -> Void)?

    func start(onAsk: @escaping (String) -> Void) {
        guard !on else { return }
        self.onAsk = onAsk
        Task {
            guard await Self.allowed() else { denied = true; return }
            do { try begin() } catch { stop() }
        }
    }

    private static func allowed() async -> Bool {
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private func begin() throws {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), rec.isAvailable else { throw URLError(.cannotConnectToHost) }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
        engine.prepare()
        try engine.start()
        words = ""; ending = false; on = true
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, self.on else { return }
                if let text, !text.isEmpty { self.heard(text) }
                if error != nil || final { self.finish() }
            }
        }
        // Nothing heard at all in 8 s: stop.
        quiet = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, self.on, self.words.isEmpty else { return }
            self.stop()
        }
    }

    /// New words: the 1.6 s count starts again.
    private func heard(_ text: String) {
        words = text
        ending = false
        quiet?.cancel()
        quiet = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            self.ending = true
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self.finish()
        }
    }

    /// Done listening: ask what was heard.
    private func finish() {
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let ask = onAsk
        stop()
        if !w.isEmpty { ask?(w) }
    }

    /// × or editing: stops without asking. Returns what was heard.
    @discardableResult
    func stop() -> String {
        let w = words
        quiet?.cancel(); quiet = nil
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        on = false; ending = false; words = ""; onAsk = nil
        return w
    }

    func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
        denied = false
    }
}

/// Read aloud: the system voice; blue while it reads, tap again to stop.
@MainActor
@Observable
final class SXSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var reading: UUID?
    private let synth = AVSpeechSynthesizer()

    override init() { super.init(); synth.delegate = self }

    func toggle(_ id: UUID, _ text: String) {
        if reading == id { synth.stopSpeaking(at: .immediate); reading = nil; return }
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        reading = id
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate); reading = nil }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.reading = nil } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {}
}
