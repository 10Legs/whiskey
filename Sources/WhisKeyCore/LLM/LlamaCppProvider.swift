import CLlama
import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "LlamaCppProvider")

/// An `LLMProvider` backed by a local GGUF model via the CLlama C bridge.
///
/// Model is loaded lazily from:
///   ~/Library/Application Support/WhisKey/Models/<modelName>.gguf
///
/// If the model file is absent at first use, the provider silently falls back to
/// `PassthroughProvider` behaviour so the user is never blocked.
public actor LlamaCppProvider: LLMProvider {

    // MARK: - Configuration

    public let modelName: String
    public let nCtx: Int32
    public let maxTokens: Int32
    public let temperature: Float
    public let nThreads: Int32

    // MARK: - State

    private var ctx: OpaquePointer?
    private var modelMissing = false

    // MARK: - Init

    public init(
        modelName: String = "phi-3.5-mini-q4_k_m",
        nCtx: Int32 = 2048,
        maxTokens: Int32 = 512,
        temperature: Float = 0.1,
        nThreads: Int32 = 4
    ) {
        self.modelName = modelName
        self.nCtx = nCtx
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.nThreads = nThreads
    }

    deinit {
        if let context = ctx {
            llama_bridge_free(context)
        }
    }

    // MARK: - LLMProvider

    public func cleanup(
        rawTranscript: String,
        context: InjectionContext,
        profile: CleanupProfile
    ) async throws -> String {
        // rawMode / literal short-circuit.
        guard !profile.rawMode, profile.toneStyle != .literal else {
            return rawTranscript
        }

        // If we already know the model is absent, passthrough.
        guard !modelMissing else {
            return rawTranscript
        }

        guard let bridgeCtx = loadContextIfNeeded() else {
            return rawTranscript
        }

        let systemPrompt = profile.toneStyle.systemPrompt
        let userPrompt = buildUserPrompt(rawTranscript: rawTranscript, profile: profile)

        // llama_bridge_complete is a blocking C call — run it off the actor executor.
        let result: String = await Task.detached(priority: .userInitiated) {
            var completion = llama_bridge_complete(
                bridgeCtx,
                systemPrompt,
                userPrompt,
                self.maxTokens,
                self.temperature
            )
            defer { llama_bridge_completion_free(&completion) }
            guard let cStr = completion.text else { return rawTranscript }
            return String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value

        return result.isEmpty ? rawTranscript : result
    }

    // MARK: - Private

    private func loadContextIfNeeded() -> OpaquePointer? {
        if let existing = ctx { return existing }

        let modelURL = modelsDirectory.appendingPathComponent("\(modelName).gguf")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            logger.warning("LlamaCppProvider: model not found at \(modelURL.path) — falling back to passthrough.")
            modelMissing = true
            return nil
        }

        guard let newCtx = llama_bridge_init(modelURL.path, nCtx, nThreads) else {
            logger.error("LlamaCppProvider: llama_bridge_init returned nil — model may be corrupt.")
            modelMissing = true
            return nil
        }

        ctx = newCtx
        logger.info("LlamaCppProvider: loaded model \(self.modelName)")
        return newCtx
    }

    private var modelsDirectory: URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return appSupport
            .appendingPathComponent("WhisKey")
            .appendingPathComponent("Models")
    }

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
        return "\(instructions.joined(separator: " "))\n\nTranscript:\n\(rawTranscript)"
    }
}
