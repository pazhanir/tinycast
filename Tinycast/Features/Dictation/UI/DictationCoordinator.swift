import AppKit
import Foundation

@MainActor
final class DictationCoordinator {
    private let settings: DictationSettingsStore
    private let appSettings: AppSettings
    private let hud: DictationHUDController
    private let recorder: DictationAudioRecorder
    let fnTapMonitor = FnTapMonitor()

    private var targetApp: NSRunningApplication?
    private var cachedAppContext: String?
    private var transcriptionTask: Task<Void, Never>?
    private var localKeyMonitor: Any?

    private(set) var isDictating = false

    init(settings: DictationSettingsStore, appSettings: AppSettings) {
        self.settings = settings
        self.appSettings = appSettings
        self.hud = DictationHUDController(settings: appSettings)
        self.recorder = DictationAudioRecorder()

        self.recorder.onAudioLevel = { [weak self] level in
            self?.hud.updateAudioLevel(level)
        }

        self.hud.onStopRequested = { [weak self] in
            self?.stopAndTranscribe()
        }

        self.hud.onCancelRequested = { [weak self] in
            self?.cancelDictation()
        }

        self.fnTapMonitor.onHoldBegan = { [weak self] in
            self?.startDictation()
        }

        self.fnTapMonitor.onHoldEnded = { [weak self] in
            self?.stopAndTranscribe()
        }

        self.fnTapMonitor.onHoldCancelled = { [weak self] in
            self?.cancelDictation()
        }

        self.fnTapMonitor.onToggle = { [weak self] in
            self?.toggleDictation()
        }

        self.settings.onTriggerModeChanged = { [weak self] in
            self?.syncTriggerPresence()
        }
        syncTriggerPresence()
    }

    func syncTriggerPresence() {
        let isFnActive = settings.isEnabled && settings.useFunctionKey
        fnTapMonitor.update(enabled: isFnActive, mode: settings.functionKeyBehavior)
    }

    func toggleDictation() {
        if isDictating {
            stopAndTranscribe()
        } else {
            startDictation()
        }
    }

    func startDictation() {
        guard !isDictating else { return }

        // Capture frontmost application before Tinycast steals any focus
        let activeApp = NSWorkspace.shared.frontmostApplication
        let isTinycastFrontmost = activeApp?.bundleIdentifier == Bundle.main.bundleIdentifier
        self.targetApp = isTinycastFrontmost ? nil : activeApp

        Task {
            let hasMicAccess = await recorder.requestMicrophonePermission()
            guard hasMicAccess else {
                hud.show(state: .error("Microphone access not granted."), providerName: "")
                return
            }

            // Extract frontmost window context if enabled
            if settings.useAppContext {
                self.cachedAppContext = DictationContextExtractor.extractContext(from: self.targetApp)
            } else {
                self.cachedAppContext = nil
            }

            do {
                try recorder.startRecording()
                self.isDictating = true

                if settings.playAudioCues {
                    NSSound(named: "Tink")?.play()
                }

                hud.show(
                    state: .listening,
                    providerName: settings.provider == .groq ? "Groq Whisper" : "macOS Speech"
                )

                installKeyMonitor()
            } catch {
                hud.show(state: .error(error.localizedDescription), providerName: "")
            }
        }
    }

    func stopAndTranscribe() {
        guard isDictating else { return }
        isDictating = false
        removeKeyMonitor()

        let pcmData = recorder.stopRecording()

        // Ignore empty / accidental taps (< ~0.25 sec of audio)
        guard pcmData.count > 16000 * 2 / 4 else {
            hud.dismiss()
            return
        }

        let wavData = WAVAudioSerializer.createWAVData(pcmData: pcmData)
        let providerName = settings.provider == .groq ? "Groq Whisper" : "macOS Speech"
        hud.show(state: .transcribing, providerName: providerName)

        let targetApplication = self.targetApp
        let prompt = DictationContextExtractor.synthesizePrompt(
            style: settings.style,
            vocabulary: settings.customVocabulary,
            appContext: cachedAppContext
        )

        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self, settings] in
            guard let self else { return }

            let engine: DictationTranscriptionEngine
            switch settings.provider {
            case .groq:
                engine = GroqWhisperClient(
                    apiKey: settings.groqApiKey,
                    model: settings.groqModel,
                    baseURLString: settings.groqBaseURL
                )
            case .onDeviceAppleSpeech:
                engine = AppleSpeechTranscriber(
                    locale: settings.language == "auto" ? .current : Locale(identifier: settings.language)
                )
            }

            do {
                let transcribedText = try await engine.transcribe(
                    wavData: wavData,
                    prompt: prompt,
                    language: settings.language
                )

                guard !Task.isCancelled else { return }

                if transcribedText.isEmpty {
                    self.hud.dismiss()
                    return
                }

                if settings.playAudioCues {
                    NSSound(named: "Purr")?.play()
                }

                self.hud.show(state: .success, providerName: providerName)

                // Paste into active app
                Paster.pasteString(transcribedText, previousApp: targetApplication)

            } catch {
                guard !Task.isCancelled else { return }
                if settings.playAudioCues {
                    NSSound(named: "Basso")?.play()
                }
                self.hud.show(state: .error(error.localizedDescription), providerName: providerName)
            }
        }
    }

    func cancelDictation() {
        guard isDictating else { return }
        isDictating = false
        removeKeyMonitor()
        recorder.cancelRecording()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        hud.dismiss()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.cancelDictation()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}
