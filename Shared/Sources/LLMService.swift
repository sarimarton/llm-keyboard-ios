import Foundation
import os.log

private let logger = Logger(subsystem: "com.sarimarton.llmkeyboard", category: "LLMService")

// MARK: - LLM Service

final class LLMService {
    static let shared = LLMService()

    private let settings = SettingsManager.shared

    private init() {}

    // MARK: - Cleanup

    func cleanup(text: String) async throws -> String {
        guard settings.enableLLMCleanup else {
            logDebug("LLM cleanup disabled, returning original text")
            return text
        }

        logDebug("Starting cleanup with service: \(settings.llmServiceType.displayName)")
        let prompt = settings.cleanupPrompt + text

        switch settings.llmServiceType {
        case .claude:
            return try await callClaudeAPI(prompt: prompt)
        case .openai, .custom:
            return try await callOpenAICompatibleAPI(prompt: prompt)
        }
    }
    
    private func logDebug(_ message: String) {
        NSLog("🔍 [LLMService] %@", message)
    }

    // MARK: - Claude API

    private func callClaudeAPI(prompt: String) async throws -> String {
        let apiKey = settings.llmAPIKey
        guard !apiKey.isEmpty else {
            logDebug("❌ Claude API key is missing")
            throw LLMError.missingAPIKey
        }

        let url = URL(string: settings.llmBaseURL + "/messages")!
        logDebug("Calling Claude API at: \(url.absoluteString)")
        logDebug("Model: \(settings.llmModelName)")

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

        logDebug("Sending request to Claude...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logDebug("❌ Invalid response type")
            throw LLMError.invalidResponse
        }

        logDebug("Response status code: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            logDebug("❌ API Error (\(httpResponse.statusCode)): \(errorText)")
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
            logDebug("❌ No text content in response")
            throw LLMError.noContent
        }

        logDebug("✅ Claude API call successful")
        return textContent
    }

    // MARK: - OpenAI Compatible API

    private func callOpenAICompatibleAPI(prompt: String) async throws -> String {
        let apiKey = settings.llmAPIKey
        guard !apiKey.isEmpty else {
            logDebug("❌ API key is missing")
            throw LLMError.missingAPIKey
        }

        let baseURL = settings.llmServiceType == .custom ? settings.llmBaseURL : settings.llmServiceType.defaultBaseURL
        guard !baseURL.isEmpty else {
            logDebug("❌ Base URL is missing")
            throw LLMError.missingBaseURL
        }

        let url = URL(string: baseURL + "/chat/completions")!
        logDebug("Calling OpenAI-compatible API at: \(url.absoluteString)")
        logDebug("Model: \(settings.llmModelName)")

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

        logDebug("Sending request...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logDebug("❌ Invalid response type")
            throw LLMError.invalidResponse
        }

        logDebug("Response status code: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            logDebug("❌ API Error (\(httpResponse.statusCode)): \(errorText)")
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
            logDebug("❌ No content in response")
            throw LLMError.noContent
        }

        logDebug("✅ API call successful")
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
