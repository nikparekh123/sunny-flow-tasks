//
//  SearchVoice.swift
//  Sunny
//
//  Ask by voice (block 27): the words appear in the box as you speak and,
//  about 1.6 s after you stop, Sunny asks on its own (Nik, Oct 28). Tap the
//  words to edit them as text; × stops. A refused microphone shows a glass
//  sheet over the box (Open Settings or Not now); typing still works.
//
//  Listening (Nik, 28 Oct 2026: "not very good with accents"): the English set
//  on the phone, not a forced American English; Apple's iOS 26 transcriber
//  (on the phone) once its model is in, the older recogniser until then (the
//  model downloads in the background the first time); and the book's tickers,
//  names and terms as hints. The question goes to Sunny marked as spoken, so
//  Claude reads a misheard word for what was meant.
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
    // The iOS 26 transcriber.
    private var analyzer: SpeechAnalyzer?
    private var feed: AsyncStream<AnalyzerInput>.Continuation?
    private var reader: Task<Void, Never>?
    // The older recogniser, until the transcriber's model is on the phone.
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var quiet: Task<Void, Never>?
    private var onAsk: ((String) -> Void)?

    func start(hints: [String], onAsk: @escaping (String) -> Void) {
        guard !on else { return }
        self.onAsk = onAsk
        Task {
            guard await Self.allowed() else { denied = true; return }
            do { try await begin(hints) } catch { stop() }
        }
    }

    private static func allowed() async -> Bool {
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// The English the phone is set to (its region too: UK, India, Australia...), else the first English in its
    /// preferred languages, else American English.
    static var locale: Locale {
        if Locale.current.language.languageCode == .english { return Locale.current }
        if let en = Locale.preferredLanguages.first(where: { $0.hasPrefix("en") }) { return Locale(identifier: en) }
        return Locale(identifier: "en-US")
    }

    private func begin(_ hints: [String]) async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        if let loc = await SpeechTranscriber.supportedLocale(equivalentTo: Self.locale) {
            let t = SpeechTranscriber(locale: loc, preset: .progressiveTranscription)
            switch await AssetInventory.status(forModules: [t]) {
            case .installed:
                do { try await beginTranscriber(t, hints); return } catch { tearDown() }
            case .supported:
                // The first time: the model downloads in the background; the older recogniser listens meanwhile.
                Task.detached { if let r = try? await AssetInventory.assetInstallationRequest(supporting: [t]) { try? await r.downloadAndInstall() } }
            default: break
            }
        }
        try beginRecogniser(hints)
    }

    private func beginTranscriber(_ t: SpeechTranscriber, _ hints: [String]) async throws {
        let a = SpeechAnalyzer(modules: [t])
        let ctx = AnalysisContext()
        ctx.contextualStrings[.general] = hints
        try await a.setContext(ctx)
        guard let want = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]) else { throw URLError(.cannotDecodeContentData) }
        try await a.prepareToAnalyze(in: want)
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        analyzer = a; feed = cont
        let input = engine.inputNode
        let have = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: have, block: Self.converting(from: have, to: want, into: cont))
        engine.prepare()
        try engine.start()
        words = ""; ending = false; on = true
        reader = Task { [weak self] in
            var done = ""
            do {
                for try await r in t.results {
                    guard let self, self.on else { return }
                    let s = String(r.text.characters)
                    if r.isFinal { done += s; self.heard(done) } else { self.heard(done + s) }
                }
            } catch {}
        }
        try await a.start(inputSequence: stream)
        waitForSpeech()
    }

    /// The microphone's buffers in the transcriber's format (the tap runs off the main thread).
    nonisolated private static func converting(from have: AVAudioFormat, to want: AVAudioFormat,
                                               into cont: AsyncStream<AnalyzerInput>.Continuation) -> AVAudioNodeTapBlock {
        let conv = have == want ? nil : AVAudioConverter(from: have, to: want)
        return { buf, _ in
            guard let conv else { cont.yield(AnalyzerInput(buffer: buf)); return }
            let cap = AVAudioFrameCount(Double(buf.frameLength) * want.sampleRate / have.sampleRate) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: want, frameCapacity: cap) else { return }
            var fed = false, err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buf
            }
            if err == nil, out.frameLength > 0 { cont.yield(AnalyzerInput(buffer: out)) }
        }
    }

    private func beginRecogniser(_ hints: [String]) throws {
        guard let rec = SFSpeechRecognizer(locale: Self.locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")), rec.isAvailable
        else { throw URLError(.cannotConnectToHost) }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        req.contextualStrings = hints
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
        waitForSpeech()
    }

    /// Nothing heard at all in 8 s: stop.
    private func waitForSpeech() {
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
        tearDown()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        on = false; ending = false; words = ""; onAsk = nil
        return w
    }

    private func tearDown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        feed?.finish(); feed = nil
        if let a = analyzer { Task { await a.cancelAndFinishNow() } }
        analyzer = nil
        reader?.cancel(); reader = nil
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
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
