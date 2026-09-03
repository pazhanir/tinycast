import Foundation

enum DictationStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case `default` = "default"
    case email = "email"
    case messaging = "messaging"
    case raw = "raw"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default:
            return "Default"
        case .email:
            return "Email"
        case .messaging:
            return "Messaging"
        case .raw:
            return "Raw (Verbatim)"
        }
    }

    var description: String {
        switch self {
        case .default:
            return "Clean, natural written text with correct punctuation, numerals, and paragraphs."
        case .email:
            return "Polished email formatting matching surrounding thread tone with greeting and closing."
        case .messaging:
            return "Casual, human, and concise formatting ideal for chat apps."
        case .raw:
            return "Exact verbatim transcription without alterations."
        }
    }

    var promptTemplate: String? {
        switch self {
        case .default:
            return """
            Write the transcript as clean, natural written text.

            - Preserve the speaker's voice, tone, and level of formality — don't make it sound more formal or more casual than how it was spoken.
            - Apply correct punctuation, capitalization, and grammar.
            - Keep questions as questions and statements as statements.
            - Write numbers as numerals ("five" → "5", "twenty dollars" → "$20").
            - Use short paragraphs when helpful for readability.
            - Format lists as proper bullet points or numbered lists when the speaker enumerates items.
            """
        case .email:
            return """
            Format the transcript as a polished email.

            - Apply correct punctuation, capitalization, and grammar.
            - Write numbers as numerals.
            - Match the surrounding thread's level of formality when clear — stay warm if the thread is warm, more professional if the thread is more formal.
            - Structure the body with clear, short, paragraphing and natural flow.
            - If the user included a greeting or closing, keep it and format it correctly ("Hi", "Hey", "Dear [Name]", "Best Regards,", "Best,", "Cheers, [Name]", etc.), otherwise do not add a greeting or closing.
            - Do not use bullet points unless the user clearly dictated a list or the thread strongly suggests list formatting.
            - Do not add a subject line.
            """
        case .messaging:
            return """
            Format the transcript as a casual written message.

            - Keep it natural, concise, and human.
            - Preserve the speaker's voice while lightly smoothing spoken phrasing into readable text.
            - Match the tone of the surrounding conversation when available.
            - Prefer direct, everyday wording.
            - Apply correct punctuation and capitalization by default, but preserve lowercase or otherwise informal stylistic tone if the surrounding conversation clearly uses it.
            - Do not make the result sound like a formal email unless the surrounding context clearly requires that tone.
            - Do not add greetings or sign-offs unless they are clearly natural in the existing conversation.
            - Keep formatting minimal.
            - Do not use bullet points unless the user clearly dictated a list or the surrounding conversation strongly suggests list formatting.
            """
        case .raw:
            return nil
        }
    }
}
