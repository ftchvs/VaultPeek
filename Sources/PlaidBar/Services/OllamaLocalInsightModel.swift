import Foundation
import PlaidBarCore

struct OllamaLocalInsightModel: LocalInsightModel {
    private let baseURL: URL
    private let configuredModelName: String?
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        configuredModelName: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.configuredModelName = configuredModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        self.session = session
    }

    func summarize(_ prompt: LocalInsightModelPrompt, maxTokens: Int) async throws -> String {
        guard Self.isLocalhost(baseURL) else {
            throw LocalInsightModelError.unsupportedConfiguration
        }

        let modelName: String
        if let configuredModelName {
            modelName = configuredModelName
        } else {
            modelName = try await discoverModelName()
        }
        let request = OllamaGenerateRequest(
            model: modelName,
            system: prompt.system,
            prompt: prompt.user,
            stream: false,
            options: OllamaGenerateOptions(
                numPredict: maxTokens,
                temperature: 0.2
            )
        )
        let response: OllamaGenerateResponse = try await postJSON(request, path: "/api/generate")
        return response.response
    }

    private func discoverModelName() async throws -> String {
        let response: OllamaTagsResponse = try await getJSON(path: "/api/tags")
        let names = response.models
            .filter(\.supportsCompletion)
            .map(\.name)

        for preferred in Self.preferredModelPrefixes {
            if let exact = names.first(where: { $0 == preferred }) {
                return exact
            }
            if let prefixed = names.first(where: { $0.hasPrefix("\(preferred):") }) {
                return prefixed
            }
        }

        guard let first = names.sorted().first else {
            throw LocalInsightModelError.noInstalledModel
        }
        return first
    }

    private func getJSON<Response: Decodable>(path: String) async throws -> Response {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let request = URLRequest(url: url)
        return try await decodeResponse(for: request)
    }

    private func postJSON<Request: Encodable, Response: Decodable>(
        _ body: Request,
        path: String
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await decodeResponse(for: request)
    }

    private func decodeResponse<Response: Decodable>(for request: URLRequest) async throws -> Response {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LocalInsightModelError.runtimeUnavailableWithDiagnostic(
                    "Ollama returned a non-HTTP response from \(requestDiagnostic(request))."
                )
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 404 {
                    throw LocalInsightModelError.noInstalledModel
                }
                throw LocalInsightModelError.runtimeUnavailableWithDiagnostic(
                    "Ollama request to \(requestDiagnostic(request)) failed with HTTP \(httpResponse.statusCode)."
                )
            }
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw LocalInsightModelError.runtimeUnavailableWithDiagnostic(
                    "Ollama response from \(requestDiagnostic(request)) could not be decoded as \(Response.self)."
                )
            }
        } catch let error as LocalInsightModelError {
            throw error
        } catch {
            throw LocalInsightModelError.runtimeUnavailableWithDiagnostic(
                "Ollama request to \(requestDiagnostic(request)) failed: \(transportDiagnostic(error))."
            )
        }
    }

    // Auto-discovery prefers small/medium INSTRUCT models. A local insight is a
    // single short summary, so a direct instruct model is the right fit. Reasoning
    // models (e.g. gpt-oss) are intentionally NOT preferred: for a short prompt
    // they spend their token budget on chain-of-thought and return an empty
    // `response`, which VaultPeek then rejects as invalid output. If a user has
    // only a reasoning model installed, discovery may still fall through to it,
    // but the empty-output probe guard surfaces an accurate error rather than
    // silently degrading.
    private static let preferredModelPrefixes = [
        "llama3.2",
        "llama3.1",
        "qwen2.5",
        "gemma3",
        "gemma2",
        "mistral",
        "phi3",
        "qwen3",
        "gemma4",
        "qwen3.5",
    ]

    private func requestDiagnostic(_ request: URLRequest) -> String {
        guard let url = request.url else { return "Ollama endpoint" }
        let host = url.host(percentEncoded: false) ?? "unknown-host"
        let endpoint = Self.diagnosticEndpointPath(from: url)
        return "\(host)\(endpoint)"
    }

    private static func diagnosticEndpointPath(from url: URL) -> String {
        let components = url.pathComponents.filter { $0 != "/" }
        guard let apiIndex = components.lastIndex(of: "api"), components.indices.contains(apiIndex + 1) else {
            return ""
        }
        return "/api/\(components[apiIndex + 1])"
    }

    private func transportDiagnostic(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) code \(nsError.code)"
    }

    static func isLocalhost(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(host)
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    let name: String
    let capabilities: [String]?

    var supportsCompletion: Bool {
        capabilities?.contains("completion") ?? true
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let system: String
    let prompt: String
    let stream: Bool
    let options: OllamaGenerateOptions
}

private struct OllamaGenerateOptions: Encodable {
    let numPredict: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case numPredict = "num_predict"
        case temperature
    }
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
