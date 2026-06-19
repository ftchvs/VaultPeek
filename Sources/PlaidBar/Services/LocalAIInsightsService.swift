import Foundation
import PlaidBarCore

private final class LocalAIProbeRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var probeTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func setTasks(probeTask: Task<Void, Never>, timeoutTask: Task<Void, Never>) {
        var shouldCancel = false
        lock.lock()
        if continuation == nil {
            shouldCancel = true
        } else {
            self.probeTask = probeTask
            self.timeoutTask = timeoutTask
        }
        lock.unlock()

        if shouldCancel {
            probeTask.cancel()
            timeoutTask.cancel()
        }
    }

    func complete(_ result: Result<String, Error>) {
        let continuationToResume: CheckedContinuation<String, Error>?
        let probeTaskToCancel: Task<Void, Never>?
        let timeoutTaskToCancel: Task<Void, Never>?

        lock.lock()
        continuationToResume = continuation
        continuation = nil
        probeTaskToCancel = probeTask
        timeoutTaskToCancel = timeoutTask
        probeTask = nil
        timeoutTask = nil
        lock.unlock()

        guard let continuationToResume else { return }

        probeTaskToCancel?.cancel()
        timeoutTaskToCancel?.cancel()

        switch result {
        case .success(let value):
            continuationToResume.resume(returning: value)
        case .failure(let error):
            continuationToResume.resume(throwing: error)
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
}

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
    /// AND-564: the Foundation Models (Apple Intelligence) insight engine, injected
    /// by the app when Apple Intelligence is available. `nil` whenever Foundation
    /// Models cannot generate (older OS, no SDK, not opted into wiring), which is
    /// the default — so the legacy generation path is untouched there.
    private let foundationModelsModel: (any LocalInsightModel)?
    /// AND-564: the probed Foundation Models availability state used by the pure
    /// routing decision. `.unsupported` by default, so FM never engages unless the
    /// app explicitly wires an `.available` state — preserving today's behavior.
    private let foundationModelsState: LocalAIFoundationModelsTierState

    init(
        model: (any LocalInsightModel)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        enabledPreference: Bool? = nil,
        modelNamePreference: String? = nil,
        autoDiscoverModel: Bool = true,
        generationConfiguration: LocalInsightModelGenerationConfiguration = .default,
        foundationModelsModel: (any LocalInsightModel)? = nil,
        foundationModelsState: LocalAIFoundationModelsTierState = .unsupported
    ) {
        self.environment = environment
        self.enabledPreference = enabledPreference
        self.model = model ?? (autoDiscoverModel ? Self.makeDefaultModel(
            environment: environment,
            enabledPreference: enabledPreference,
            modelNamePreference: modelNamePreference
        ) : nil)
        self.generationConfiguration = generationConfiguration
        self.foundationModelsModel = foundationModelsModel
        self.foundationModelsState = foundationModelsState
    }

    /// The on-device AI tier this service would prefer to *generate* insights
    /// with, given the FM probe state and whether the opted-in Ollama runtime is
    /// engaged. Mirrors the tier resolver AppState surfaces in Settings.
    private var preferredTier: LocalAIRuntimeTier {
        LocalAITierResolver.resolvePreferredTier(
            facts: LocalAITierFacts(
                foundationModels: foundationModelsState,
                ollamaEngaged: LocalAIRuntimeResolution.usesModel(for: availability.state),
                naturalLanguageReady: Self.naturalLanguageTierReady
            )
        )
    }

    /// Whether Foundation Models is the active, available generation engine for
    /// this service (AND-564). When `false`, the existing engine path runs exactly
    /// as it did before FM existed. Delegates to the pure, unit-tested selector so
    /// the runtime and the regression tests share one decision.
    private var foundationModelsActive: Bool {
        FoundationModelsInsightEngineSelector.selectEngine(
            foundationModelsModelWired: foundationModelsModel != nil,
            preferredTier: preferredTier,
            foundationModelsState: foundationModelsState
        ) == .foundationModels
    }

    /// The NaturalLanguage categorizer ships whenever the framework imports, which
    /// on macOS is always.
    private static var naturalLanguageTierReady: Bool {
        #if canImport(NaturalLanguage)
        true
        #else
        false
        #endif
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
            let probeOutput = try await boundedProbe(model: model)
            // A model that responds but emits nothing usable (e.g. a reasoning
            // model that spends a short token budget on chain-of-thought and
            // returns an empty `response`) must NOT be reported as available —
            // the real summary call would hit the same empty output and be
            // rejected. Surface it as invalid output with an actionable hint
            // instead of falsely claiming the runtime is healthy.
            guard !probeOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return LocalAIRuntimeResolution.resolved(
                    base: currentAvailability,
                    usedModelOutput: false,
                    fallbackReason: .invalidOutput,
                    fallbackDiagnostic: "Local runtime returned an empty response. This usually means a reasoning model is configured; set an instruct model such as llama3.2."
                )
            }
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
        let timeoutNanoseconds = generationConfiguration.timeoutNanoseconds
        return try await withCheckedThrowingContinuation { continuation in
            let race = LocalAIProbeRace(continuation: continuation)

            let probeTask = Task {
                do {
                    let result = try await model.summarize(
                        LocalInsightModelPrompt(
                            system: "Reply with OK if the local runtime is available. Do not include financial data.",
                            user: "Health check only."
                        ),
                        maxTokens: 8
                    )
                    race.complete(.success(result))
                } catch {
                    race.complete(.failure(error))
                }
            }

            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    race.complete(.failure(LocalInsightModelError.runtimeUnavailableWithDiagnostic("Local AI health probe timed out.")))
                } catch {
                    race.cancelTimeout()
                }
            }
            race.setTasks(probeTask: probeTask, timeoutTask: timeoutTask)
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
        // AND-564: route generation through Foundation Models ONLY when it is the
        // active, available tier; otherwise feed the existing engine exactly as
        // before. When FM is inactive, `foundationModelsActive` is false and this
        // collapses to the pre-AND-564 selection — the regression guard.
        let useFoundationModels = foundationModelsActive
        let configuredModel: (any LocalInsightModel)?
        // The base availability `resolved(...)` upgrades from. For FM we synthesize
        // a `.checking` base so a successful FM generation reports `.available`
        // even when the Ollama runtime is `.disabled`/unconfigured (a user can have
        // Apple Intelligence without ever opting into Ollama). Non-FM keeps the
        // exact pre-AND-564 base.
        let baseAvailability: LocalAIAvailability
        if useFoundationModels {
            configuredModel = foundationModelsModel
            baseAvailability = Self.foundationModelsBaseAvailability
        } else {
            configuredModel = LocalAIRuntimeResolution.usesModel(for: currentAvailability.state) ? model : nil
            baseAvailability = currentAvailability
        }

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
                base: baseAvailability,
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

    /// Base availability used when Foundation Models generates the summary
    /// (AND-564). `.checking` so a successful generation upgrades to `.available`
    /// via `resolved(...)`, and a failed one degrades to `.unavailable` with the
    /// Apple Intelligence runtime name — never silently reading as `.disabled`.
    private static let foundationModelsBaseAvailability = LocalAIAvailability(
        state: .checking,
        runtimeName: LocalAIRuntimeTier.foundationModels.shortStatusLabel,
        detail: "Verifying Apple Intelligence on-device generation. VaultPeek keeps the data on this Mac, validates output, and falls back to deterministic local summaries."
    )

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
