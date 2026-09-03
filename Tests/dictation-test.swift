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
        // 1. Single Tap Mode
        var singleDetector = FnTapDetector(targetTaps: 1)
        let r1 = singleDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 1.0)
        check("Single tap: press alone does not trigger", r1 == false)
        let r2 = singleDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 1.15)
        check("Single tap: release triggers dictation", r2 == true)

        // 2. Double Tap Mode
        var doubleDetector = FnTapDetector(targetTaps: 2)
        _ = doubleDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 2.0)
        let d1 = doubleDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 2.1)
        check("Double tap: first tap does not trigger", d1 == false)
        _ = doubleDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 2.3)
        let d2 = doubleDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 2.4)
        check("Double tap: second tap triggers dictation", d2 == true)

        // 3. Triple Tap Mode
        var tripleDetector = FnTapDetector(targetTaps: 3)
        _ = tripleDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 3.0)
        _ = tripleDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 3.1)
        _ = tripleDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 3.25)
        _ = tripleDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 3.35)
        _ = tripleDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 3.5)
        let t3 = tripleDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 3.6)
        check("Triple tap: third tap triggers dictation", t3 == true)

        // 4. Invalidation on other key input
        var cancelDetector = FnTapDetector(targetTaps: 2)
        _ = cancelDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 4.0)
        _ = cancelDetector.handle(.otherInput, at: 4.05)
        let c1 = cancelDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 4.1)
        check("Other key input cancels tap sequence", c1 == false)

        // 5. Invalidation when other modifiers held (e.g. Cmd+Fn)
        var modDetector = FnTapDetector(targetTaps: 1)
        let m1 = modDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: true), at: 5.0)
        let m2 = modDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: true), at: 5.1)
        check("Fn with other modifiers does not trigger", m1 == false && m2 == false)

        // 6. Held too long (hold > 0.4s is not a tap)
        var holdDetector = FnTapDetector(targetTaps: 1)
        _ = holdDetector.handle(.fnFlag(isHeld: true, hasOtherModifiers: false), at: 6.0)
        let h1 = holdDetector.handle(.fnFlag(isHeld: false, hasOtherModifiers: false), at: 6.5)
        check("Fn held longer than maxHold does not trigger", h1 == false)
    }
}
