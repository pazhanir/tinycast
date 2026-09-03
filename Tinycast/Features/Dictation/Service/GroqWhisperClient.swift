import Foundation

struct GroqWhisperClient: DictationTranscriptionEngine {
    let apiKey: String
    let model: String
    let baseURL: URL

    init(
        apiKey: String,
        model: String = "whisper-large-v3-turbo",
        baseURL: URL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    func transcribe(
        wavData: Data,
        prompt: String?,
        language: String?
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "GroqWhisperClient",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Groq API key is missing. Add your key in Settings › Dictation."]
            )
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 1. Audio file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // 2. Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // 3. Response format field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)

        // 4. Language field (if specified)
        if let lang = language?.trimmingCharacters(in: .whitespacesAndNewlines), !lang.isEmpty, lang.lowercased() != "auto" {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lang)\r\n".data(using: .utf8)!)
        }

        // 5. Prompt conditioning field (Style + Vocabulary + App Context)
        if let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(prompt)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GroqWhisperClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
            let message = errorMsg?["message"] as? String ?? String(data: data, encoding: .utf8) ?? "Transcription failed (\(httpResponse.statusCode))."
            throw NSError(domain: "GroqWhisperClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        struct WhisperResponse: Codable {
            let text: String
        }

        let decoded = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
