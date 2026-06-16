import Foundation
import PlaidBarCore

struct LocalAIInsightsService: Sendable {
    private enum EnvironmentKeys {
        static let localRuntime = LocalAIRuntimeResolution.optInEnvironmentKey
        static let ollamaBaseURL = "PLAIDBAR_OLLAMA_BASE_URL"
        static let ollamaModel = "PLAIDBAR_LOCAL_AI_MODEL"
    }

    private let model: (any LocalInsightModel)?
    private let environment: [String: String]
    private let enabledPreference: Bool?
    private let generationConfiguration: LocalInsightModelGenerationConfiguration

    init(
        model: (any LocalInsightModel)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        enabledPreference: Bool? = nil,
        modelNamePreference: String? = nil,
        autoDiscoverModel: Bool = true,
        generationConfiguration: LocalInsightModelGenerationConfiguration = .default
    ) {
        self.environment = environment
        self.enabledPreference = enabledPreference
        self.model = model ?? (autoDiscoverModel ? Self.makeDefaultModel(
            environment: environment,
            enabledPreference: enabledPreference,
            modelNamePreference: modelNamePreference
        ) : nil)
        self.generationConfiguration = generationConfiguration
    }

    var availability: LocalAIAvailability {
        LocalAIRuntimeResolution.configuredAvailability(
            enabledPreference: enabledPreference,
            rawValue: environment[EnvironmentKeys.localRuntime],
            hasWiredModel: model != nil,
            endpointIsLocalhost: Self.endpointIsLocalhost(environment: environment)
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

    func probeAvailability() async -> LocalAIAvailability {
        let currentAvailability = availability
        guard LocalAIRuntimeResolution.usesModel(for: currentAvailability.state), let model else {
            return currentAvailability
        }

        do {
            _ = try await boundedProbe(model: model)
            return LocalAIRuntimeResolution.resolved(
                base: currentAvailability,
                usedModelOutput: true,
                fallbackReason: nil
            )
        } catch let error as LocalInsightModelError {
            let reason: LocalInsightModelFallbackReason
            let diagnostic: String?
            switch error {
            case .runtimeUnavailable:
                reason = .runtimeUnavailable
                diagnostic = nil
            case .runtimeUnavailableWithDiagnostic(let message):
                reason = .runtimeUnavailable
                diagnostic = message
            case .noInstalledModel:
                reason = .noInstalledModel
                diagnostic = nil
            case .unsupportedConfiguration:
                reason = .unsupportedConfiguration
                diagnostic = nil
            }
            return LocalAIRuntimeResolution.resolved(
                base: currentAvailability,
                usedModelOutput: false,
                fallbackReason: reason,
                fallbackDiagnostic: diagnostic
            )
        } catch {
            return LocalAIRuntimeResolution.resolved(
                base: currentAvailability,
                usedModelOutput: false,
                fallbackReason: .modelError,
                fallbackDiagnostic: String(describing: error)
            )
        }
    }

    private func boundedProbe(model: any LocalInsightModel) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await model.summarize(
                    LocalInsightModelPrompt(
                        system: "Reply with OK if the local runtime is available. Do not include financial data.",
                        user: "Health check only."
                    ),
                    maxTokens: 8
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: generationConfiguration.timeoutNanoseconds)
                throw LocalInsightModelError.runtimeUnavailableWithDiagnostic("Local AI health probe timed out.")
            }

            guard let result = try await group.next() else {
                throw LocalInsightModelError.runtimeUnavailable
            }
            group.cancelAll()
            return result
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
        let configuredModel = LocalAIRuntimeResolution.usesModel(for: currentAvailability.state) ? model : nil

        for input in inputs {
            // Cooperative cancellation: a multi-page sync reschedules this work
            // repeatedly. Stop launching model calls once the owning task is
            // cancelled so a superseded refresh does not keep hitting the runtime.
            if Task.isCancelled { break }

            let fallbackSummary: @Sendable (LocalAIActivitySummaryInput) -> String = { input in
                Self.summaryText(for: input)
            }
            let generated = await LocalInsightModelRuntime.generateSummary(
                input: input,
                model: configuredModel,
                fallbackSummary: fallbackSummary,
                configuration: generationConfiguration
            )
            let summaryAvailability = LocalAIRuntimeResolution.resolved(
                base: currentAvailability,
                usedModelOutput: generated.usedModelOutput,
                fallbackReason: generated.fallbackReason,
                fallbackDiagnostic: generated.fallbackDiagnostic
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

    /// Construct the on-device model ONLY when the user has explicitly opted in
    /// via persisted app settings or (`PLAIDBAR_LOCAL_AI_RUNTIME=ollama`/`auto`)
    /// and the endpoint is localhost. An unset app setting plus unset variable
    /// yields `nil` — no transaction-derived prompt data is routed to any process
    /// listening on localhost without consent.
    private static func makeDefaultModel(
        environment: [String: String],
        enabledPreference: Bool?,
        modelNamePreference: String?
    ) -> (any LocalInsightModel)? {
        guard LocalAIRuntimeResolution.isOptedIn(
            enabledPreference: enabledPreference,
            rawValue: environment[EnvironmentKeys.localRuntime]
        ) else {
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
            configuredModelName: Self.configuredModelName(
                modelNamePreference: modelNamePreference,
                environment: environment
            )
        )
    }

    private static func configuredModelName(
        modelNamePreference: String?,
        environment: [String: String]
    ) -> String? {
        modelNamePreference?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? environment[EnvironmentKeys.ollamaModel]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
    }

    /// Whether a configured custom endpoint (if any) is localhost. A missing or
    /// unparseable custom endpoint means the default localhost endpoint is used.
    private static func endpointIsLocalhost(environment: [String: String]) -> Bool {
        guard let rawBaseURL = environment[EnvironmentKeys.ollamaBaseURL]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawBaseURL.isEmpty,
            let baseURL = URL(string: rawBaseURL)
        else {
            return true
        }
        return OllamaLocalInsightModel.isLocalhost(baseURL)
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
