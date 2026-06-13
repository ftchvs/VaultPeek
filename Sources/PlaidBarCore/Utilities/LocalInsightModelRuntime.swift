import Foundation

public struct LocalInsightModelGenerationConfiguration: Sendable, Equatable {
    public static let `default` = LocalInsightModelGenerationConfiguration()

    public let maxTokens: Int
    public let maxOutputCharacters: Int
    public let timeoutNanoseconds: UInt64

    public init(
        maxTokens: Int = 96,
        maxOutputCharacters: Int = 320,
        timeoutNanoseconds: UInt64 = 1_500_000_000
    ) {
        self.maxTokens = max(1, maxTokens)
        self.maxOutputCharacters = max(80, maxOutputCharacters)
        self.timeoutNanoseconds = max(1_000_000, timeoutNanoseconds)
    }
}

public enum LocalInsightModelFallbackReason: String, Sendable, Hashable {
    case noModel
    case timeout
    case modelError
    case invalidOutput
}

public struct LocalInsightModelGenerationResult: Sendable, Equatable {
    public let summary: String
    public let usedModelOutput: Bool
    public let fallbackReason: LocalInsightModelFallbackReason?

    public init(
        summary: String,
        usedModelOutput: Bool,
        fallbackReason: LocalInsightModelFallbackReason?
    ) {
        self.summary = summary
        self.usedModelOutput = usedModelOutput
        self.fallbackReason = fallbackReason
    }
}

public enum LocalInsightModelOutputRejectionReason: String, Sendable, Hashable {
    case empty
    case echoedPrompt
    case garbage
}

public enum LocalInsightModelOutputValidationResult: Sendable, Equatable {
    case accepted(String)
    case rejected(LocalInsightModelOutputRejectionReason)
}

public enum LocalInsightModelOutputValidator {
    public static func validate(
        _ output: String,
        prompt: LocalInsightModelPrompt,
        maxCharacters: Int = LocalInsightModelGenerationConfiguration.default.maxOutputCharacters
    ) -> LocalInsightModelOutputValidationResult {
        let normalized = normalizedDisplayText(output)

        guard !normalized.isEmpty else {
            return .rejected(.empty)
        }

        guard !looksLikePromptEcho(normalized, prompt: prompt) else {
            return .rejected(.echoedPrompt)
        }

        guard !looksLikeGarbage(normalized) else {
            return .rejected(.garbage)
        }

        let capped = String(normalized.prefix(max(1, maxCharacters)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !capped.isEmpty else {
            return .rejected(.empty)
        }

        return .accepted(capped)
    }

    private static func normalizedDisplayText(_ output: String) -> String {
        output
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikePromptEcho(
        _ output: String,
        prompt: LocalInsightModelPrompt
    ) -> Bool {
        let normalizedOutput = normalizedForComparison(output)
        let promptParts = [prompt.system, prompt.user]
            + prompt.system.components(separatedBy: .newlines)
            + prompt.user.components(separatedBy: .newlines)

        for part in promptParts {
            let normalizedPart = normalizedForComparison(part)
            if normalizedPart.count >= 24, normalizedOutput.contains(normalizedPart) {
                return true
            }
        }

        let lowercasedOutput = output.lowercased()
        if lowercasedOutput.hasPrefix("period:") || lowercasedOutput.hasPrefix("totals:") {
            return true
        }

        let promptMarkers = [
            "period:",
            "totals:",
            "top categories:",
            "largest expenses:",
            "versus the prior period:",
            "estimated recurring monthly cost:",
            "you are vaultpeek",
            "rules:",
        ]
        let markerCount = promptMarkers.reduce(0) { count, marker in
            lowercasedOutput.contains(marker) ? count + 1 : count
        }
        return markerCount >= 2
    }

    private static func looksLikeGarbage(_ output: String) -> Bool {
        if output.contains("\u{FFFD}") {
            return true
        }

        let scalars = output.unicodeScalars
        if scalars.contains(where: { scalar in
            scalar.value < 32 && scalar.value != 9 && scalar.value != 10 && scalar.value != 13
        }) {
            return true
        }

        let nonWhitespace = Array(scalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        guard !nonWhitespace.isEmpty else {
            return true
        }

        let alphanumericCount = nonWhitespace.filter { CharacterSet.alphanumerics.contains($0) }.count
        if alphanumericCount < 12 {
            return true
        }

        let alphanumericRatio = Double(alphanumericCount) / Double(nonWhitespace.count)
        if alphanumericRatio < 0.35 {
            return true
        }

        return longestRepeatedScalarRun(in: nonWhitespace) >= 16
    }

    private static func longestRepeatedScalarRun(in scalars: [UnicodeScalar]) -> Int {
        var longest = 0
        var currentRun = 0
        var previous: UnicodeScalar?

        for scalar in scalars {
            if scalar == previous {
                currentRun += 1
            } else {
                currentRun = 1
                previous = scalar
            }
            longest = max(longest, currentRun)
        }

        return longest
    }

    private static func normalizedForComparison(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public enum LocalInsightModelRuntime {
    public static func generateSummary(
        input: LocalAIActivitySummaryInput,
        model: (any LocalInsightModel)?,
        fallbackSummary: @Sendable (LocalAIActivitySummaryInput) -> String,
        configuration: LocalInsightModelGenerationConfiguration = .default
    ) async -> LocalInsightModelGenerationResult {
        let fallback = fallbackSummary(input)
        guard let model else {
            return LocalInsightModelGenerationResult(
                summary: fallback,
                usedModelOutput: false,
                fallbackReason: .noModel
            )
        }

        let prompt = LocalInsightPromptBuilder.make(from: input)
        let rawOutput: String

        do {
            rawOutput = try await withTimeout(nanoseconds: configuration.timeoutNanoseconds) {
                try await model.summarize(prompt, maxTokens: configuration.maxTokens)
            }
        } catch is LocalInsightModelTimeoutError {
            return LocalInsightModelGenerationResult(
                summary: fallback,
                usedModelOutput: false,
                fallbackReason: .timeout
            )
        } catch {
            return LocalInsightModelGenerationResult(
                summary: fallback,
                usedModelOutput: false,
                fallbackReason: .modelError
            )
        }

        switch LocalInsightModelOutputValidator.validate(
            rawOutput,
            prompt: prompt,
            maxCharacters: configuration.maxOutputCharacters
        ) {
        case .accepted(let summary):
            return LocalInsightModelGenerationResult(
                summary: summary,
                usedModelOutput: true,
                fallbackReason: nil
            )
        case .rejected:
            return LocalInsightModelGenerationResult(
                summary: fallback,
                usedModelOutput: false,
                fallbackReason: .invalidOutput
            )
        }
    }

    private static func withTimeout<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw LocalInsightModelTimeoutError()
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw LocalInsightModelTimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

private struct LocalInsightModelTimeoutError: Error {}
