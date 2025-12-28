import Foundation

// MARK: - LLM Service

final class LLMService {
    static let shared = LLMService()

    private let settings = SettingsManager.shared

    private init() {}

    // MARK: - Cleanup

    func cleanup(text: String) async throws -> String {
        guard settings.enableLLMCleanup else {
            return text
        }

        let prompt = settings.cleanupPrompt + text

        switch settings.llmServiceType {
        case .claude:
            return try await callClaudeAPI(prompt: prompt)
        case .openai, .custom:
            return try await callOpenAICompatibleAPI(prompt: prompt)
        }
    }

    // MARK: - Claude API

    private func callClaudeAPI(prompt: String) async throws -> String {
        let apiKey = settings.llmAPIKey
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        let url = URL(string: settings.llmBaseURL + "/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": settings.llmModelName,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(httpResponse.statusCode, errorText)
        }

        // Parse Claude response
        struct ClaudeResponse: Codable {
            struct Content: Codable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }

        let result = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let textContent = result.content.first(where: { $0.type == "text" })?.text else {
            throw LLMError.noContent
        }

        return textContent
    }

    // MARK: - OpenAI Compatible API

    private func callOpenAICompatibleAPI(prompt: String) async throws -> String {
        let apiKey = settings.llmAPIKey
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        let baseURL = settings.llmServiceType == .custom ? settings.llmBaseURL : settings.llmServiceType.defaultBaseURL
        guard !baseURL.isEmpty else {
            throw LLMError.missingBaseURL
        }

        let url = URL(string: baseURL + "/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": settings.llmModelName,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 4096
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(httpResponse.statusCode, errorText)
        }

        // Parse OpenAI response
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let content = result.choices.first?.message.content else {
            throw LLMError.noContent
        }

        return content
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case missingAPIKey
    case missingBaseURL
    case invalidResponse
    case apiError(Int, String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is missing. Please add it in Settings."
        case .missingBaseURL:
            return "Base URL is missing for custom service."
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .noContent:
            return "No content in response"
        }
    }
}
