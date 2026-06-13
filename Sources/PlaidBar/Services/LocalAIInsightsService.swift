import Foundation
import PlaidBarCore

struct LocalAIInsightsService: Sendable {
    private enum EnvironmentKeys {
        static let localRuntime = "PLAIDBAR_LOCAL_AI_RUNTIME"
        static let ollamaBaseURL = "PLAIDBAR_OLLAMA_BASE_URL"
        static let ollamaModel = "PLAIDBAR_LOCAL_AI_MODEL"
    }

    private let model: (any LocalInsightModel)?
    private let environment: [String: String]
    private let generationConfiguration: LocalInsightModelGenerationConfiguration

    init(
        model: (any LocalInsightModel)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        autoDiscoverModel: Bool = true,
        generationConfiguration: LocalInsightModelGenerationConfiguration = .default
    ) {
        self.environment = environment
        self.model = model ?? (autoDiscoverModel ? Self.makeDefaultModel(environment: environment) : nil)
        self.generationConfiguration = generationConfiguration
    }

    var availability: LocalAIAvailability {
        let runtime = Self.configuredRuntimeName(environment: environment)
        guard !Self.isDisabledRuntimeValue(runtime) else {
            return LocalAIAvailability(
                state: .disabled,
                detail: "Local AI is disabled. VaultPeek is using deterministic local summaries and category hints only."
            )
        }

        if model != nil {
            return LocalAIAvailability(
                state: .available,
                runtimeName: runtime,
                detail: "Local runtime '\(runtime)' is wired automatically. VaultPeek only talks to localhost, validates output, and falls back to deterministic local summaries."
            )
        }

        return LocalAIAvailability(
            state: .unavailable,
            runtimeName: runtime,
            detail: Self.unavailableConfigurationDetail(runtime: runtime, environment: environment)
        )
    }

    func activitySummaries(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        recurringTransactions: [RecurringTransaction],
        anchorDate: Date = Date()
    ) -> [LocalAIActivitySummary] {
        let inputs = LocalAIInsightInputBuilder.buildInputs(
            accounts: accounts,
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            anchorDate: anchorDate
        )

        return inputs.map { input in
            LocalAIActivitySummary(
                window: input.window,
                availability: availability,
                input: input,
                generatedSummary: Self.summaryText(for: input),
                generatedBullets: Self.bullets(for: input),
                evidence: input.evidence
            )
        }
    }

    func generatedActivitySummaries(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        recurringTransactions: [RecurringTransaction],
        anchorDate: Date = Date()
    ) async -> [LocalAIActivitySummary] {
        let inputs = LocalAIInsightInputBuilder.buildInputs(
            accounts: accounts,
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            anchorDate: anchorDate
        )

        var summaries: [LocalAIActivitySummary] = []
        summaries.reserveCapacity(inputs.count)
        let currentAvailability = availability
        let configuredModel = currentAvailability.state == .available ? model : nil

        for input in inputs {
            let fallbackSummary: @Sendable (LocalAIActivitySummaryInput) -> String = { input in
                Self.summaryText(for: input)
            }
            let generated = await LocalInsightModelRuntime.generateSummary(
                input: input,
                model: configuredModel,
                fallbackSummary: fallbackSummary,
                configuration: generationConfiguration
            )
            let summaryAvailability = Self.summaryAvailability(
                baseAvailability: currentAvailability,
                generationResult: generated
            )
            summaries.append(
                LocalAIActivitySummary(
                    window: input.window,
                    availability: summaryAvailability,
                    input: input,
                    generatedSummary: generated.summary,
                    generatedBullets: Self.bullets(for: input),
                    evidence: input.evidence
                )
            )
        }

        return summaries
    }

    private static func isDisabledRuntimeValue(_ rawValue: String) -> Bool {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || ["disabled", "off", "false", "none"].contains(normalized)
    }

    private static func configuredRuntimeName(environment: [String: String]) -> String {
        let runtime = environment[EnvironmentKeys.localRuntime]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let runtime, !runtime.isEmpty else {
            return "ollama"
        }
        return runtime
    }

    private static func makeDefaultModel(environment: [String: String]) -> (any LocalInsightModel)? {
        let runtime = configuredRuntimeName(environment: environment)
        guard !isDisabledRuntimeValue(runtime),
              ["auto", "ollama"].contains(runtime.lowercased())
        else {
            return nil
        }

        let baseURL = environment[EnvironmentKeys.ollamaBaseURL]
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? URL(string: "http://127.0.0.1:11434")!
        guard OllamaLocalInsightModel.isLocalhost(baseURL) else {
            return nil
        }

        return OllamaLocalInsightModel(
            baseURL: baseURL,
            configuredModelName: environment[EnvironmentKeys.ollamaModel]
        )
    }

    private static func unavailableConfigurationDetail(
        runtime: String,
        environment: [String: String]
    ) -> String {
        let normalizedRuntime = runtime.lowercased()
        if !["auto", "ollama"].contains(normalizedRuntime) {
            return "Local runtime '\(runtime)' is configured, but this build only auto-wires local Ollama. Deterministic summaries remain active; cloud models are not supported."
        }

        if let rawBaseURL = environment[EnvironmentKeys.ollamaBaseURL],
           let baseURL = URL(string: rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
           !OllamaLocalInsightModel.isLocalhost(baseURL)
        {
            return "Ollama must be configured on localhost. VaultPeek refused the non-local endpoint and used deterministic summaries without cloud fallback."
        }

        return "Local Ollama could not be configured. Deterministic summaries remain active; cloud models are not supported."
    }

    private static func summaryAvailability(
        baseAvailability: LocalAIAvailability,
        generationResult: LocalInsightModelGenerationResult
    ) -> LocalAIAvailability {
        guard baseAvailability.state == .available,
              generationResult.usedModelOutput == false,
              let fallbackReason = generationResult.fallbackReason
        else {
            return baseAvailability
        }

        return LocalAIAvailability(
            state: .unavailable,
            runtimeName: baseAvailability.runtimeName,
            detail: fallbackDetail(runtimeName: baseAvailability.runtimeName, reason: fallbackReason)
        )
    }

    private static func fallbackDetail(
        runtimeName: String?,
        reason: LocalInsightModelFallbackReason
    ) -> String {
        let runtime = runtimeName.map { "Local runtime '\($0)'" } ?? "The configured local runtime"
        let reasonText = switch reason {
        case .noModel:
            "has no model adapter"
        case .runtimeUnavailable:
            "is not reachable on this Mac"
        case .noInstalledModel:
            "has no installed local model"
        case .unsupportedConfiguration:
            "is configured with an unsupported local endpoint"
        case .timeout:
            "timed out before producing output"
        case .modelError:
            "returned an error"
        case .invalidOutput:
            "returned invalid output"
        }
        return "\(runtime) \(reasonText). VaultPeek used deterministic local summaries and did not call cloud AI."
    }

    private static func summaryText(for input: LocalAIActivitySummaryInput) -> String {
        let expenseText = Formatters.currency(input.current.expenseTotal, format: .compact)
        let incomeText = Formatters.currency(input.current.incomeTotal, format: .compact)
        let netText = signedCurrency(input.current.netCashflow)
        return "\(input.window.displayName): \(expenseText) expenses, \(incomeText) income, \(netText) net cashflow."
    }

    private static func bullets(for input: LocalAIActivitySummaryInput) -> [String] {
        var bullets: [String] = []

        if let topCategory = input.current.categoryTotals.first {
            bullets
                .append(
                    "\(topCategory.category.displayName) led expenses at \(Formatters.currency(topCategory.totalAmount, format: .compact)) from \(topCategory.transactionCount) transaction\(topCategory.transactionCount == 1 ? "" : "s")."
                )
        }

        if let topExpense = input.current.topExpenses.first {
            bullets
                .append(
                    "Largest outflow was \(topExpense.displayName) at \(Formatters.currency(topExpense.amount, format: .compact))."
                )
        }

        if let prior = input.prior, prior.expenseTotal > 0 {
            let delta = input.current.expenseTotal - prior.expenseTotal
            let direction = delta >= 0 ? "up" : "down"
            bullets
                .append(
                    "Expenses are \(direction) \(Formatters.currency(abs(delta), format: .compact)) versus the comparison window."
                )
        }

        if input.current.netCashflow != 0 {
            bullets.append("Net cashflow is \(signedCurrency(input.current.netCashflow)) after income and expenses.")
        }

        if input.recurringSnapshot.estimatedMonthlyTotal > 0 {
            bullets
                .append(
                    "Recurring charges estimate \(Formatters.currency(input.recurringSnapshot.estimatedMonthlyTotal, format: .compact)) per month."
                )
        }

        if bullets.isEmpty {
            bullets.append("No transaction activity is available for this local summary window.")
        }

        return Array(bullets.prefix(4))
    }

    private static func signedCurrency(_ amount: Double) -> String {
        let prefix = amount > 0 ? "+" : amount < 0 ? "-" : ""
        return "\(prefix)\(Formatters.currency(abs(amount), format: .compact))"
    }
}
