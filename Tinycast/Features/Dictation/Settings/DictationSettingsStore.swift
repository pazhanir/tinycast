import Foundation
import Observation

@Observable
final class DictationSettingsStore {
    private let defaults: UserDefaults
    private let keyStore: KeychainSecretStore

    private static let groqAccountKey = "groq-api-key"

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    var provider: DictationProvider {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }

    var groqBaseURL: String {
        didSet { defaults.set(groqBaseURL, forKey: Keys.groqBaseURL) }
    }

    var groqModel: String {
        didSet { defaults.set(groqModel, forKey: Keys.groqModel) }
    }

    var language: String {
        didSet { defaults.set(language, forKey: Keys.language) }
    }

    var style: DictationStyle {
        didSet { defaults.set(style.rawValue, forKey: Keys.style) }
    }

    var useAppContext: Bool {
        didSet { defaults.set(useAppContext, forKey: Keys.useAppContext) }
    }

    var customVocabulary: String {
        didSet { defaults.set(customVocabulary, forKey: Keys.customVocabulary) }
    }

    var playAudioCues: Bool {
        didSet { defaults.set(playAudioCues, forKey: Keys.playAudioCues) }
    }

    var groqApiKey: String = "" {
        didSet {
            try? keyStore.setSecret(groqApiKey, for: Self.groqAccountKey)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        keyStore: KeychainSecretStore = .dictation
    ) {
        self.defaults = defaults
        self.keyStore = keyStore

        self.isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        let savedProvider = defaults.string(forKey: Keys.provider).flatMap(DictationProvider.init) ?? .groq
        self.provider = savedProvider
        self.groqBaseURL = defaults.string(forKey: Keys.groqBaseURL) ?? "https://api.groq.com/openai/v1"
        self.groqModel = defaults.string(forKey: Keys.groqModel) ?? "whisper-large-v3-turbo"
        self.language = defaults.string(forKey: Keys.language) ?? "auto"
        let savedStyle = defaults.string(forKey: Keys.style).flatMap(DictationStyle.init) ?? .default
        self.style = savedStyle
        self.useAppContext = defaults.object(forKey: Keys.useAppContext) as? Bool ?? true
        self.customVocabulary = defaults.string(forKey: Keys.customVocabulary) ?? ""
        self.playAudioCues = defaults.object(forKey: Keys.playAudioCues) as? Bool ?? true

        if let savedKey = try? keyStore.secret(for: Self.groqAccountKey) {
            self.groqApiKey = savedKey
        }
    }

    private enum Keys {
        static let isEnabled = "dictation.isEnabled"
        static let provider = "dictation.provider"
        static let groqBaseURL = "dictation.groqBaseURL"
        static let groqModel = "dictation.groqModel"
        static let language = "dictation.language"
        static let style = "dictation.style"
        static let useAppContext = "dictation.useAppContext"
        static let customVocabulary = "dictation.customVocabulary"
        static let playAudioCues = "dictation.playAudioCues"
    }
}
