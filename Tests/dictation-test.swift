// Tests for Whisper Dictation models, serializers, styles, and prompt synthesis.

import Foundation
import NaturalLanguage

@main
@MainActor
struct DictationTests {
    static var failures = 0
    static var passes = 0

    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func main() {
        testWAVSerializer()
        testStyles()
        testProviders()
        testPromptSynthesis()
        testFnTapDetector()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - WAV Audio Serializer

    static func testWAVSerializer() {
        let dummyPCM = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        let wav = WAVAudioSerializer.createWAVData(pcmData: dummyPCM, sampleRate: 16000, channels: 1)

        check("WAV data contains 44-byte header + pcm", wav.count == 44 + dummyPCM.count, "got \(wav.count)")

        // Check RIFF header
        let riff = String(decoding: wav.prefix(4), as: UTF8.self)
        check("RIFF marker is present", riff == "RIFF", "got \(riff)")

        let wave = String(decoding: wav[8..<12], as: UTF8.self)
        check("WAVE marker is present", wave == "WAVE", "got \(wave)")

        let fmt = String(decoding: wav[12..<16], as: UTF8.self)
        check("fmt marker is present", fmt == "fmt ", "got \(fmt)")

        let data = String(decoding: wav[36..<40], as: UTF8.self)
        check("data marker is present", data == "data", "got \(data)")

        // Check data size field in header (bytes 40..<44)
        let dataSize = wav[40..<44].withUnsafeBytes { $0.load(as: UInt32.self) }
        check("Data size matches pcm count", dataSize == UInt32(dummyPCM.count), "got \(dataSize)")
    }

    // MARK: - Styles

    static func testStyles() {
        check("DictationStyle has 4 cases", DictationStyle.allCases.count == 4)
        check("Default style has non-empty prompt", !(DictationStyle.default.promptTemplate?.isEmpty ?? true))

        let emailPrompt = DictationStyle.email.promptTemplate ?? ""
        check("Email style contains subject or greeting instruction",
              emailPrompt.contains("email") || emailPrompt.contains("paragraph"))

        let msgPrompt = DictationStyle.messaging.promptTemplate ?? ""
        check("Messaging style contains casual instruction",
              msgPrompt.contains("casual") || msgPrompt.contains("messaging"))

        check("Raw style prompt template is nil", DictationStyle.raw.promptTemplate == nil)
    }

    // MARK: - Providers

    static func testProviders() {
        check("Groq provider id matches", DictationProvider.groq.id == "groq")
        check("OnDevice provider id matches", DictationProvider.onDeviceAppleSpeech.id == "onDeviceAppleSpeech")
    }

    // MARK: - Prompt Synthesis

    static func testPromptSynthesis() {
        let sampleContext = "App: Xcode\nNames: Alice Smith\nOrganizations: Google"
        let prompt = DictationContextExtractor.synthesizePrompt(
            style: .default,
            vocabulary: "Pazhani, Kubernetes",
            appContext: sampleContext
        )

        guard let prompt else {
            check("Synthesized prompt is not nil", false)
            return
        }

        check("Synthesized prompt contains custom vocabulary", prompt.contains("Kubernetes"), "got \(prompt)")
        check("Synthesized prompt contains custom author name", prompt.contains("Pazhani"), "got \(prompt)")
        check("Synthesized prompt contains default style guidance", prompt.contains("clean, natural written text"), "got \(prompt)")
        check("Synthesized prompt contains window context", prompt.contains("App: Xcode"), "got \(prompt)")
    }

    // MARK: - Fn Tap Detector

    static func testFnTapDetector() {
        // 1. Hold to Talk Mode
        var holdDetector = FnTapDetector(mode: .holdToTalk)
        let h1 = holdDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 1.0)
        check("Hold to talk: Fn down begins hold", h1 == .holdBegan)

        let h2 = holdDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 3.5)
        check("Hold to talk: Fn up ends hold", h2 == .holdEnded)

        // Hold to Talk cancelled by other key (e.g. Fn + Delete)
        var holdCancelDetector = FnTapDetector(mode: .holdToTalk)
        _ = holdCancelDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 4.0)
        let hc = holdCancelDetector.handle(.otherInput, at: 4.2)
        check("Hold to talk: other key press cancels hold", hc == .holdCancelled)

        // Hold to Talk ignored when modifiers held
        var modDetector = FnTapDetector(mode: .holdToTalk)
        let hm = modDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: true), at: 5.0)
        check("Hold to talk: Fn with other modifiers ignored", hm == .none)

        // 2. Press to Toggle Mode
        var toggleDetector = FnTapDetector(mode: .pressToToggle)
        let t1 = toggleDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 6.0)
        check("Press to toggle: Fn down emits none", t1 == .none)

        let t2 = toggleDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 6.15)
        check("Press to toggle: Fn up within maxTapDuration toggles", t2 == .toggleTriggered)

        // Press to toggle ignored if held too long (> 0.40s)
        var longHoldDetector = FnTapDetector(mode: .pressToToggle)
        _ = longHoldDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 7.0)
        let lt = longHoldDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 7.5)
        check("Press to toggle: held > maxTapDuration is ignored", lt == .none)

        // Press to toggle cancelled if typing occurs
        var typingDetector = FnTapDetector(mode: .pressToToggle)
        _ = typingDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 8.0)
        _ = typingDetector.handle(.otherInput, at: 8.1)
        let tt = typingDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 8.2)
        check("Press to toggle: typing cancels toggle", tt == .none)
    }
}
