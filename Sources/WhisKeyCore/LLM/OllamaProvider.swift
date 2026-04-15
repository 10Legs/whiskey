import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "OllamaProvider")

/// An `LLMProvider` that sends cleanup requests to a locally-running Ollama instance.
///
/// Endpoint: `http://localhost:11434/api/generate` (non-streaming).
/// Timeout: 10 seconds. On any failure (network error, timeout, non-200 response),
/// returns the raw transcript unchanged so the user is never blocked.
public struct OllamaProvider: LLMProvider {

    // MARK: - Configuration

    /// Ollama model tag to use (e.g. "llama3.2").
    public let modelName: String

    /// Base URL of the Ollama server.
    public let baseURL: URL

    // MARK: - Init

    public init(
        modelName: String = "llama3.2",
        baseURL: URL = URL(string: "http://localhost:11434")! // swiftlint:disable:this force_unwrapping
    ) {
        self.modelName = modelName
        self.baseURL = baseURL
    }

    // MARK: - LLMProvider

    public func cleanup(
        rawTranscript: String,
        context: InjectionContext,
        profile: CleanupProfile
    ) async throws -> String {
        // rawMode short-circuit — skip LLM entirely.
        guard !profile.rawMode, profile.toneStyle != .literal else {
            return rawTranscript
        }

        let endpoint = baseURL.appendingPathComponent("api/generate")

        let prompt = buildUserPrompt(rawTranscript: rawTranscript, profile: profile)
        let body: [String: Any] = [
            "model": modelName,
            "system": profile.toneStyle.systemPrompt,
            "prompt": prompt,
            "stream": false
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            logger.warning("OllamaProvider: failed to serialize request body — returning raw transcript.")
            return rawTranscript
        }

        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.warning("OllamaProvider: non-200 response (\(code)) — returning raw transcript.")
                return rawTranscript
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cleaned = json["response"] as? String {
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            logger.warning("OllamaProvider: could not parse response JSON — returning raw transcript.")
            return rawTranscript

        } catch {
            logger.warning("OllamaProvider: request failed (\(error.localizedDescription)) — returning raw transcript.")
            return rawTranscript
        }
    }

    // MARK: - Private

    private func buildUserPrompt(rawTranscript: String, profile: CleanupProfile) -> String {
        var instructions: [String] = []
        if profile.removeFillers {
            instructions.append("Remove filler words (um, uh, like, you know, basically, actually).")
        }
        if profile.addPunctuation {
            instructions.append("Add correct punctuation and capitalize sentence starts.")
        }
        if instructions.isEmpty {
            instructions.append("Lightly clean the following transcript.")
        }
        let instructionText = instructions.joined(separator: " ")
        return "\(instructionText)\n\nTranscript:\n\(rawTranscript)"
    }
}
