import Foundation
import OSLog

public struct LocalInsightModelGenerationConfiguration: Sendable, Equatable {
    public static let `default` = LocalInsightModelGenerationConfiguration()

    public let maxTokens: Int
    public let maxOutputCharacters: Int
    public let timeoutNanoseconds: UInt64

    public init(
        maxTokens: Int = 96,
        maxOutputCharacters: Int = 320,
        timeoutNanoseconds: UInt64 = 8_000_000_000
    ) {
        self.maxTokens = max(1, maxTokens)
        self.maxOutputCharacters = max(80, maxOutputCharacters)
        self.timeoutNanoseconds = max(1_000_000, timeoutNanoseconds)
    }
}

public enum LocalInsightModelFallbackReason: String, Sendable, Hashable {
    case noModel
    case runtimeUnavailable
    case noInstalledModel
    case unsupportedConfiguration
    case timeout
    case modelError
    case invalidOutput
}

public struct LocalInsightModelGenerationResult: Sendable, Equatable {
    public let summary: String
    public let usedModelOutput: Bool
    public let fallbackReason: LocalInsightModelFallbackReason?
    public let fallbackDiagnostic: String?

    public init(
        summary: String,
        usedModelOutput: Bool,
        fallbackReason: LocalInsightModelFallbackReason?,
        fallbackDiagnostic: String? = nil
    ) {
        self.summary = summary
        self.usedModelOutput = usedModelOutput
        self.fallbackReason = fallbackReason
        self.fallbackDiagnostic = fallbackDiagnostic
    }
}

public enum LocalInsightModelOutputRejectionReason: String, Sendable, Hashable {
    case empty
    case echoedPrompt
    case garbage
    /// Advice, recommendations, predictions, or AI self-disclosure — content the
    /// system prompt forbids. A local model can ignore instructions, so this is
    /// enforced rather than trusted.
    case prohibitedContent
    /// A currency figure that does not appear in the redaction-safe prompt, i.e.
    /// a likely invented amount. Finance copy must not surface unverifiable
    /// numbers.
    case unverifiedFigure
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

        guard !containsProhibitedContent(normalized) else {
            return .rejected(.prohibitedContent)
        }

        guard !containsUnverifiedFigure(normalized, prompt: prompt) else {
            return .rejected(.unverifiedFigure)
        }

        let capped = String(normalized.prefix(max(1, maxCharacters)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !capped.isEmpty else {
            return .rejected(.empty)
        }

        return .accepted(capped)
    }

    /// Phrases that signal advice, recommendations, predictions, or AI
    /// self-disclosure. A factual, past-tense spending summary should contain
    /// none of these; when one appears, fall back to the deterministic summary
    /// rather than render unsanctioned guidance in a finance surface.
    private static let prohibitedPhrases = [
        // Advice / recommendations
        "you should", "i recommend", "we recommend", "i suggest", "i'd suggest",
        "i would suggest", "my advice", "i advise", "you might want", "you may want",
        "consider ", "you could ", "it's advisable", "it is advisable", "make sure to",
        "cut back", "cut down", "reduce your", "spend less", "save money",
        "you can save", "to save", "try to ", "you ought to",
        // Predictions / forward-looking
        "will likely", "likely to", "you'll likely", "next month", "next week",
        "expect to", "you can expect", "is expected", "are expected", "going forward",
        "in the future", "projected", "forecast", "by next", "will probably",
        "you will spend", "you'll spend", "is going to", "are going to",
        // AI self-disclosure
        "as an ai", "as a language model", "i am an ai", "i'm an ai",
        "language model", "as your assistant", "i cannot provide", "i can't provide",
    ]

    private static func containsProhibitedContent(_ output: String) -> Bool {
        let lowercased = output.lowercased()
        return prohibitedPhrases.contains { lowercased.contains($0) }
    }

    /// Reject any `$`-denominated figure in the output that is not present in the
    /// redaction-safe prompt (the only legitimate source of numbers). Catches
    /// invented amounts; figures are matched by numeric value so cents/comma
    /// formatting differences do not cause false rejections.
    private static func containsUnverifiedFigure(
        _ output: String,
        prompt: LocalInsightModelPrompt
    ) -> Bool {
        let outputValues = currencyValues(in: output)
        guard !outputValues.isEmpty else { return false }

        let allowed = currencyValues(in: prompt.user).union(currencyValues(in: prompt.system))
        return outputValues.contains { value in
            !allowed.contains { abs($0 - value) < 0.5 }
        }
    }

    /// Extract the numeric value of every `$`-prefixed amount in `text`
    /// (`$1,234.56`, `$420`, `$ 12`). Thousands separators are dropped; a
    /// trailing sentence period is not treated as a decimal point.
    private static func currencyValues(in text: String) -> Set<Double> {
        var values: Set<Double> = []
        let scalars = Array(text.unicodeScalars)
        var index = 0

        while index < scalars.count {
            guard scalars[index] == "$" else {
                index += 1
                continue
            }

            var cursor = index + 1
            if cursor < scalars.count, scalars[cursor] == " " {
                cursor += 1
            }

            var digits = ""
            while cursor < scalars.count {
                let scalar = scalars[cursor]
                if scalar.value >= 48, scalar.value <= 57 {
                    digits.unicodeScalars.append(scalar)
                    cursor += 1
                } else if scalar == "," {
                    cursor += 1
                } else if scalar == ".",
                          cursor + 1 < scalars.count,
                          scalars[cursor + 1].value >= 48, scalars[cursor + 1].value <= 57 {
                    // Decimal point only when followed by a digit; a period that
                    // ends a sentence ("$420.") is not part of the number.
                    digits.unicodeScalars.append(scalar)
                    cursor += 1
                } else {
                    break
                }
            }

            if !digits.isEmpty, let value = Double(digits) {
                values.insert(value)
            }
            index = max(cursor, index + 1)
        }

        return values
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
    private static let logger = Logger(
        subsystem: "com.ftchvs.PlaidBar",
        category: "LocalInsightModelRuntime"
    )

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
        let actionName = "generateSummary"
        let modelID = String(reflecting: type(of: model))
        let startedAt = Date()
        let rawOutput: String

        do {
            rawOutput = try await withTimeout(nanoseconds: configuration.timeoutNanoseconds) {
                try await model.summarize(prompt, maxTokens: configuration.maxTokens)
            }
        } catch is LocalInsightModelTimeoutError {
            recordModelFailure(
                actionName: actionName,
                modelID: modelID,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt),
                reason: .timeout
            )
            return LocalInsightModelGenerationResult(
                summary: fallback,
                usedModelOutput: false,
                fallbackReason: .timeout
            )
        } catch let error as LocalInsightModelError {
            let reason = error.fallbackReason
            let diagnostic = error.diagnostic
            recordModelFailure(
                actionName: actionName,
                modelID: modelID,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt),
                reason: reason,
                diagnostic: diagnostic
            )
            return LocalInsightModelGenerationResult(
                summary: fallback,
                usedModelOutput: false,
                fallbackReason: reason,
                fallbackDiagnostic: diagnostic
            )
        } catch {
            recordModelFailure(
                actionName: actionName,
                modelID: modelID,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt),
                reason: .modelError
            )
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

    private static func recordModelFailure(
        actionName: String,
        modelID: String,
        elapsedMilliseconds: Int,
        reason: LocalInsightModelFallbackReason,
        diagnostic: String? = nil
    ) {
        if let diagnostic {
            logger.warning(
                "local_insight_model_failure action=\(actionName, privacy: .public) model_id=\(modelID, privacy: .public) elapsed_ms=\(elapsedMilliseconds) reason=\(reason.rawValue, privacy: .public) diagnostic=\(diagnostic, privacy: .public)"
            )
        } else {
            logger.warning(
                "local_insight_model_failure action=\(actionName, privacy: .public) model_id=\(modelID, privacy: .public) elapsed_ms=\(elapsedMilliseconds) reason=\(reason.rawValue, privacy: .public)"
            )
        }
    }

    private static func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }

    private static func withTimeout<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let race = LocalInsightModelTimeoutRace<T>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let operationTask = Task {
                    do {
                        let result = try await operation()
                        race.complete(.success(result))
                    } catch {
                        race.complete(.failure(error))
                    }
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                        race.complete(.failure(LocalInsightModelTimeoutError()))
                    } catch {
                        race.cancelTimeout()
                    }
                }
                race.start(
                    continuation: continuation,
                    operationTask: operationTask,
                    timeoutTask: timeoutTask
                )
            }
        } onCancel: {
            race.complete(.failure(CancellationError()))
        }
    }
}

private final class LocalInsightModelTimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completedResult: Result<T, Error>?

    func start(
        continuation: CheckedContinuation<T, Error>,
        operationTask: Task<Void, Never>,
        timeoutTask: Task<Void, Never>
    ) {
        let resultToResume: Result<T, Error>?

        lock.lock()
        resultToResume = completedResult
        if resultToResume == nil {
            self.continuation = continuation
            self.operationTask = operationTask
            self.timeoutTask = timeoutTask
        }
        lock.unlock()

        guard let resultToResume else {
            return
        }

        operationTask.cancel()
        timeoutTask.cancel()
        resume(continuation, with: resultToResume)
    }

    func complete(_ result: Result<T, Error>) {
        let continuationToResume: CheckedContinuation<T, Error>?
        let operationTaskToCancel: Task<Void, Never>?
        let timeoutTaskToCancel: Task<Void, Never>?

        lock.lock()
        guard completedResult == nil else {
            lock.unlock()
            return
        }
        completedResult = result
        continuationToResume = continuation
        continuation = nil
        operationTaskToCancel = operationTask
        timeoutTaskToCancel = timeoutTask
        operationTask = nil
        timeoutTask = nil
        lock.unlock()

        operationTaskToCancel?.cancel()
        timeoutTaskToCancel?.cancel()

        if let continuationToResume {
            resume(continuationToResume, with: result)
        }
    }

    func cancelTimeout() {
        let timeoutTaskToCancel: Task<Void, Never>?

        lock.lock()
        timeoutTaskToCancel = timeoutTask
        timeoutTask = nil
        lock.unlock()

        timeoutTaskToCancel?.cancel()
    }

    private func resume(_ continuation: CheckedContinuation<T, Error>, with result: Result<T, Error>) {
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private struct LocalInsightModelTimeoutError: Error {}

private extension LocalInsightModelError {
    var fallbackReason: LocalInsightModelFallbackReason {
        switch self {
        case .runtimeUnavailable, .runtimeUnavailableWithDiagnostic:
            .runtimeUnavailable
        case .noInstalledModel:
            .noInstalledModel
        case .unsupportedConfiguration:
            .unsupportedConfiguration
        }
    }

    var diagnostic: String? {
        switch self {
        case .runtimeUnavailableWithDiagnostic(let diagnostic):
            diagnostic
        case .runtimeUnavailable, .noInstalledModel, .unsupportedConfiguration:
            nil
        }
    }
}
