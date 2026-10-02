import Foundation
import SwiftUI

// MARK: - AI provider adapter
//
// Tomo talks to any provider through one call: `TomoAI.complete(system:user:)`.
// Anthropic uses its own Messages API; every other preset speaks the OpenAI-compatible
// chat format (OpenAI, Gemini, OpenRouter, Groq, Ollama, LM Studio, or any custom endpoint).
// Settings live in UserDefaults; the API key lives in the Keychain.

enum TomoAIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case anthropic, openai, gemini, openrouter, groq, ollama, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anthropic:  "Anthropic (Claude)"
        case .openai:     "OpenAI"
        case .gemini:     "Google Gemini"
        case .openrouter: "OpenRouter"
        case .groq:       "Groq"
        case .ollama:     "Ollama (local, free)"
        case .custom:     "Custom (OpenAI-compatible)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic:  "https://api.anthropic.com/v1"
        case .openai:     "https://api.openai.com/v1"
        case .gemini:     "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openrouter: "https://openrouter.ai/api/v1"
        case .groq:       "https://api.groq.com/openai/v1"
        case .ollama:     "http://localhost:11434/v1"
        case .custom:     ""
        }
    }

    /// Prefilled model; for the others, use "Fetch models" in the AI window.
    /// gpt-5.4-mini: checked against /v1/models and a test turn on 2026-10-03 (good toddler Japanese, ~2 s).
    var defaultModel: String {
        switch self {
        case .anthropic: "claude-haiku-4-5-20251001"
        case .openai:    "gpt-5.4-mini"
        default:         ""
        }
    }

    var needsKey: Bool { self != .ollama }
}

struct TomoAIConfig: Codable, Equatable, Sendable {
    var provider: TomoAIProvider = .anthropic
    var baseURL: String = TomoAIProvider.anthropic.defaultBaseURL
    var model: String = TomoAIProvider.anthropic.defaultModel
    var apiKey: String = ""          // never persisted with the rest (Keychain only)

    var isUsable: Bool {
        !model.isEmpty && !baseURL.isEmpty && (!provider.needsKey || !apiKey.isEmpty)
    }
    var label: String { "\(provider.title.components(separatedBy: " (").first ?? provider.title) · \(model)" }
}

struct TomoAIError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
enum TomoAI {
    private static let defaultsKey = "tomoAIConfig"
    private static let keychainKey = "tomo-ai-api-key"
    private static var cachedKey: String?

    /// The saved configuration, with its key. With nothing saved, OPENAI_API_KEY or ANTHROPIC_API_KEY from the
    /// environment is used (mac-demo/run.sh loads ../.env). TOMO_AI_PROVIDER / _MODEL / _BASE_URL / _KEY override all (testing).
    static var config: TomoAIConfig {
        var c = TomoAIConfig()
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(TomoAIConfig.self, from: data) { c = saved }
        if cachedKey == nil { cachedKey = Keychain.load(key: keychainKey) ?? "" }
        c.apiKey = cachedKey ?? ""
        let env = ProcessInfo.processInfo.environment
        if !c.isUsable {
            for (name, p) in [("OPENAI_API_KEY", TomoAIProvider.openai), ("ANTHROPIC_API_KEY", .anthropic)] {
                if let k = env[name], !k.isEmpty {
                    c = TomoAIConfig(provider: p, baseURL: p.defaultBaseURL, model: p.defaultModel, apiKey: k)
                    break
                }
            }
        }
        if let p = env["TOMO_AI_PROVIDER"].flatMap(TomoAIProvider.init(rawValue:)) {
            c = TomoAIConfig(provider: p, baseURL: p.defaultBaseURL, model: p.defaultModel, apiKey: "")
        }
        if let m = env["TOMO_AI_MODEL"] { c.model = m }
        if let u = env["TOMO_AI_BASE_URL"] { c.baseURL = u }
        if let k = env["TOMO_AI_KEY"] { c.apiKey = k }
        return c
    }

    static func save(_ c: TomoAIConfig) {
        var stored = c
        stored.apiKey = ""
        if let data = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(data, forKey: defaultsKey) }
        if c.apiKey.isEmpty { Keychain.delete(key: keychainKey) } else { Keychain.save(key: keychainKey, value: c.apiKey) }
        cachedKey = c.apiKey
    }

    // MARK: Calls (nonisolated: run off the main actor)

    /// One-shot completion: system prompt + user text → assistant text.
    nonisolated static func complete(system: String, user: String, config c: TomoAIConfig) async throws -> String {
        let base = c.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if c.provider == .anthropic {
            let body: [String: Any] = [
                "model": c.model, "max_tokens": 300, "system": system,
                "messages": [["role": "user", "content": user]],
            ]
            let json = try await post("\(base)/messages", body: body, headers: anthropicHeaders(c))
            guard let text = (json["content"] as? [[String: Any]])?.first?["text"] as? String
            else { throw TomoAIError(message: "Unexpected response from \(c.provider.title).") }
            return text
        }
        // OpenAI-compatible chat completions. Only model + messages, so every provider accepts it.
        let body: [String: Any] = [
            "model": c.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        let json = try await post("\(base)/chat/completions", body: body, headers: bearerHeaders(c))
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String
        else { throw TomoAIError(message: "Unexpected response from \(c.provider.title).") }
        return text
    }

    /// Model IDs the endpoint offers (GET /models works on every preset).
    nonisolated static func listModels(config c: TomoAIConfig) async throws -> [String] {
        let base = c.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/models") else { throw TomoAIError(message: "Invalid base URL.") }
        var req = URLRequest(url: url, timeoutInterval: 10)
        let headers = c.provider == .anthropic ? anthropicHeaders(c) : bearerHeaders(c)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let json = try await send(req)
        let ids = (json["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        // Gemini prefixes ids with "models/"
        return ids.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
    }

    nonisolated private static func anthropicHeaders(_ c: TomoAIConfig) -> [String: String] {
        ["x-api-key": c.apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json"]
    }

    nonisolated private static func bearerHeaders(_ c: TomoAIConfig) -> [String: String] {
        var h = ["content-type": "application/json"]
        if !c.apiKey.isEmpty { h["authorization"] = "Bearer \(c.apiKey)" }
        return h
    }

    nonisolated private static func post(_ urlString: String, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw TomoAIError(message: "Invalid base URL.") }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    nonisolated private static func send(_ req: URLRequest) async throws -> [String: Any] {
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw TomoAIError(message: "Couldn't reach \(req.url?.host ?? "the server"): \(error.localizedDescription)") }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let detail = ((json["error"] as? [String: Any])?["message"] as? String)
                ?? String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw TomoAIError(message: "HTTP \(status): \(detail)")
        }
        return json
    }
}

// MARK: - "AI provider" window

struct TomoAISettingsView: View {
    @ObservedObject var lang = TomoLanguages.shared
    @State private var config = TomoAI.config
    @State private var models: [String] = []
    @State private var status = ""
    @State private var busy = false

    var body: some View {
        Form {
            Picker(lang.learner("ai.provider"), selection: $config.provider) {
                ForEach(TomoAIProvider.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: config.provider) { _, p in
                config.baseURL = p.defaultBaseURL
                config.model = p.defaultModel
                models = []
                status = ""
            }

            TextField(lang.learner("ai.baseURL"), text: $config.baseURL)
            SecureField(lang.learner(config.provider.needsKey ? "ai.key" : "ai.keyNotNeeded"), text: $config.apiKey)

            HStack {
                TextField(lang.learner("ai.model"), text: $config.model)
                if !models.isEmpty {
                    Picker("", selection: $config.model) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                Button(lang.learner("ai.fetch")) { fetchModels() }.disabled(busy)
            }

            HStack {
                Button(lang.learner("ai.save")) { TomoAI.save(config); status = lang.learner("ai.saved", ["label": config.label]) }
                    .keyboardShortcut(.defaultAction)
                Button(lang.learner("ai.test")) { test() }.disabled(busy || !config.isUsable)
                if busy { ProgressView().controlSize(.small) }
            }

            if !status.isEmpty {
                Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(lang.learner("ai.footer"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private func fetchModels() {
        busy = true; status = lang.learner("ai.loading")
        let c = config
        Task {
            do {
                let ids = try await TomoAI.listModels(config: c)
                models = ids.sorted()
                if config.model.isEmpty || !ids.contains(config.model) {
                    config.model = ids.first { ["haiku", "mini", "flash", "small", "8b"].contains(where: $0.contains) } ?? ids.first ?? ""
                }
                status = lang.learner("ai.count", ["n": "\(ids.count)"])
            } catch { status = error.localizedDescription }
            busy = false
        }
    }

    private func test() {
        busy = true; status = lang.learner("ai.asking")
        let c = config
        Task {
            switch await TomoBrain.test(config: c, language: TomoLanguages.shared.context) {
            case .success(let r): status = "Tomo: \(r.say)  (\(r.translation))  understood: \(r.understood)"
            case .failure(let e): status = e.localizedDescription
            }
            busy = false
        }
    }
}
