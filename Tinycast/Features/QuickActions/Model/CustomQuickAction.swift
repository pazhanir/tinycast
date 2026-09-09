import Foundation

/// A user-defined Quick Action (AI Command) powered by Dynamic Placeholders.
struct CustomQuickAction: Identifiable, Codable, Hashable, Sendable {
    enum OutputMode: String, Codable, CaseIterable, Sendable {
        case previewInPanel = "previewInPanel"
        case openInAIChat = "openInAIChat"
        case replaceSelection = "replaceSelection"
        case copyToClipboard = "copyToClipboard"
        case insertBelow = "insertBelow"

        var title: String {
            switch self {
            case .previewInPanel: return "Preview in Panel"
            case .openInAIChat: return "Open in AI Chat"
            case .replaceSelection: return "Replace Selection"
            case .copyToClipboard: return "Copy to Clipboard"
            case .insertBelow: return "Insert Below"
            }
        }

        var symbol: String {
            switch self {
            case .previewInPanel: return "macwindow"
            case .openInAIChat: return "bubble.left.and.bubble.right"
            case .replaceSelection: return "arrow.triangle.2.circlepath"
            case .copyToClipboard: return "doc.on.clipboard"
            case .insertBelow: return "text.append"
            }
        }
    }

    var id: UUID
    var name: String
    var descriptionText: String
    var prompt: String
    var symbol: String
    var outputMode: OutputMode
    var model: AIModelSelection?
    var isEnabled: Bool

    var replacesDirectly: Bool {
        outputMode == .replaceSelection
    }

    init(
        id: UUID = UUID(),
        name: String,
        descriptionText: String = "",
        prompt: String,
        symbol: String = "wand.and.sparkles",
        outputMode: OutputMode = .previewInPanel,
        model: AIModelSelection? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.prompt = prompt
        self.symbol = symbol
        self.outputMode = outputMode
        self.model = model
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id, name, descriptionText, prompt, symbol, outputMode, replacesDirectly, model, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Custom Action"
        descriptionText = try container.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "wand.and.sparkles"
        if let decodedOutput = try container.decodeIfPresent(OutputMode.self, forKey: .outputMode) {
            outputMode = decodedOutput
        } else if let replaces = try container.decodeIfPresent(Bool.self, forKey: .replacesDirectly) {
            outputMode = replaces ? .replaceSelection : .previewInPanel
        } else {
            outputMode = .previewInPanel
        }
        model = try container.decodeIfPresent(AIModelSelection.self, forKey: .model)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(descriptionText, forKey: .descriptionText)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(outputMode, forKey: .outputMode)
        try container.encode(replacesDirectly, forKey: .replacesDirectly)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    static let sampleActions: [CustomQuickAction] = [
        CustomQuickAction(
            name: "Explain Selection",
            descriptionText: "Explain selected text or code in detail",
            prompt: "Explain the following text clearly and concisely:\n\n{selection}",
            symbol: "questionmark.circle",
            outputMode: .previewInPanel
        ),
        CustomQuickAction(
            name: "Ask AI Chat About Selection",
            descriptionText: "Send selection to AI Chat for follow-up discussion",
            prompt: "Here is context from my active application:\n\n{selection}\n\nCan you explain this and suggest improvements?",
            symbol: "bubble.left.and.bubble.right",
            outputMode: .openInAIChat
        ),
        CustomQuickAction(
            name: "Translate to French",
            descriptionText: "Translate selection into French",
            prompt: "Translate the following text into natural French. Return only the translation:\n\n{selection}",
            symbol: "character.book.closed",
            outputMode: .previewInPanel
        ),
        CustomQuickAction(
            name: "Format as Bullet Points",
            descriptionText: "Convert selection into neat bullet points",
            prompt: "Convert the following information into clean, concise bullet points:\n\n{selection}",
            symbol: "list.bullet",
            outputMode: .replaceSelection
        )
    ]
}
