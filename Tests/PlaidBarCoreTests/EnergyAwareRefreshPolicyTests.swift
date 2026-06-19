import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Energy-aware refresh policy")
struct EnergyAwareRefreshPolicyTests {
    private let baseInterval: TimeInterval = 15 * 60 // matches PlaidBarConstants.backgroundRefreshInterval

    // MARK: - Thermal severity mapping

    @Test("Thermal severity classifies nominal/fair as normal and serious/critical as constrained")
    func thermalSeverityClassification() {
        #expect(EnergyAwareRefreshPolicy.EnergyThermalState.nominal.isConstrained == false)
        #expect(EnergyAwareRefreshPolicy.EnergyThermalState.fair.isConstrained == false)
        #expect(EnergyAwareRefreshPolicy.EnergyThermalState.serious.isConstrained == true)
        #expect(EnergyAwareRefreshPolicy.EnergyThermalState.critical.isConstrained == true)
    }

    // MARK: - shouldRunAutomaticRefresh

    @Test("Normal power and thermal: automatic refresh proceeds when otherwise due")
    func normalConditionsProceed() {
        let conditions = EnergyAwareRefreshPolicy.EnergyConditions(
            lowPowerMode: false,
            thermalState: .nominal
        )
        #expect(EnergyAwareRefreshPolicy.shouldRunAutomaticRefresh(
            conditions: conditions,
            automaticRefreshIsDue: true,
            isManual: false
        ) == true)
    }

    @Test("Low power mode defers an otherwise-due automatic refresh")
    func lowPowerDefers() {
        let conditions = EnergyAwareRefreshPolicy.EnergyConditions(
            lowPowerMode: true,
            thermalState: .nominal
        )
        #expect(EnergyAwareRefreshPolicy.shouldRunAutomaticRefresh(
            conditions: conditions,
            automaticRefreshIsDue: true,
            isManual: false
        ) == false)
    }

    @Test("Serious thermal state defers an otherwise-due automatic refresh")
    func seriousThermalDefers() {
        let conditions = EnergyAwareRefreshPolicy.EnergyConditions(
            lowPowerMode: false,
            thermalState: .serious
        )
        #expect(EnergyAwareRefreshPolicy.shouldRunAutomaticRefresh(
            conditions: conditions,
            automaticRefreshIsDue: true,
            isManual: false
        ) == false)
    }

    @Test("Critical thermal state defers an otherwise-due automatic refresh")
    func criticalThermalDefers() {
        let conditions = EnergyAwareRefreshPolicy.EnergyConditions(
            lowPowerMode: false,
            thermalState: .critical
        )
        #expect(EnergyAwareRefreshPolicy.shouldRunAutomaticRefresh(
            conditions: conditions,
            automaticRefreshIsDue: true,
            isManual: false
        ) == false)
    }

    @Test("Manual refresh always runs, even in low power and critical thermal")
    func manualAlwaysAllowed() {
        let worstCase = EnergyAwareRefreshPolicy.EnergyConditions(
            lowPowerMode: true,
            thermalState: .critical
        )
        // Manual runs even when the time-based policy says it is not due.
        #expect(EnergyAwareRefreshPolicy.shouldRunAutomaticRefresh(
            conditions: worstCase,
            automaticRefreshIsDue: false,
            isManual: true
        ) == true)
        #expect(EnergyAwareRefreshPolicy.shouldRunAutomaticRefresh(
            conditions: worstCase,
            automaticRefreshIsDue: true,
            isManual: true
        ) == true)
    }

    @Test("Automatic refresh that is not yet due never runs regardless of energy")
    func notDueNeverRunsAutomatically() {
        let normal = EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: false, thermalState: .nominal)
        #expect(EnergyAwareRefreshPolicy.shouldRunAutomaticRefresh(
            conditions: normal,
            automaticRefreshIsDue: false,
            isManual: false
        ) == false)
    }

    @Test("Constrained energy must back off even when low power mode is off but thermal is hot")
    func constrainedByThermalOnly() {
        let conditions = EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: false, thermalState: .serious)
        #expect(conditions.isConstrained == true)
        #expect(EnergyAwareRefreshPolicy.shouldRunAutomaticRefresh(
            conditions: conditions,
            automaticRefreshIsDue: true,
            isManual: false
        ) == false)
    }

    // MARK: - Backoff math (next tick delay)

    @Test("Next tick delay equals the base interval when energy is normal")
    func normalDelayIsBaseInterval() {
        let normal = EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: false, thermalState: .nominal)
        #expect(EnergyAwareRefreshPolicy.nextTickDelay(
            baseInterval: baseInterval,
            conditions: normal
        ) == baseInterval)
    }

    @Test("Constrained energy lengthens the next tick delay by the backoff multiplier")
    func constrainedDelayBacksOff() {
        let lowPower = EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: true, thermalState: .nominal)
        let hot = EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: false, thermalState: .critical)
        let expected = baseInterval * EnergyAwareRefreshPolicy.constrainedBackoffMultiplier
        #expect(EnergyAwareRefreshPolicy.nextTickDelay(baseInterval: baseInterval, conditions: lowPower) == expected)
        #expect(EnergyAwareRefreshPolicy.nextTickDelay(baseInterval: baseInterval, conditions: hot) == expected)
    }

    @Test("Backoff multiplier is greater than one so constrained ticks are strictly less frequent")
    func backoffMultiplierLengthens() {
        #expect(EnergyAwareRefreshPolicy.constrainedBackoffMultiplier > 1)
        let normal = EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: false, thermalState: .nominal)
        let constrained = EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: true, thermalState: .nominal)
        #expect(
            EnergyAwareRefreshPolicy.nextTickDelay(baseInterval: baseInterval, conditions: constrained)
                > EnergyAwareRefreshPolicy.nextTickDelay(baseInterval: baseInterval, conditions: normal)
        )
    }

    @Test("Next tick delay is clamped to a sane finite floor for non-finite or non-positive base intervals")
    func delayHandlesDegenerateBaseInterval() {
        let normal = EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: false, thermalState: .nominal)
        let zero = EnergyAwareRefreshPolicy.nextTickDelay(baseInterval: 0, conditions: normal)
        let negative = EnergyAwareRefreshPolicy.nextTickDelay(baseInterval: -42, conditions: normal)
        let infinite = EnergyAwareRefreshPolicy.nextTickDelay(baseInterval: .infinity, conditions: normal)
        for value in [zero, negative, infinite] {
            #expect(value.isFinite)
            #expect(value > 0)
        }
    }

    @Test("Constrained back-off never overflows to infinity for a finite-but-huge base interval")
    func constrainedDelayNeverOverflowsToInfinity() {
        let constrained = EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: true, thermalState: .nominal)
        // A finite, positive base that overflows once multiplied by the backoff
        // multiplier: the product is no longer finite, so the policy must fall
        // back to the (finite) sanitized base rather than sleeping forever.
        let hugeBase = Double.greatestFiniteMagnitude
        let result = EnergyAwareRefreshPolicy.nextTickDelay(baseInterval: hugeBase, conditions: constrained)
        #expect(result.isFinite)
        #expect(result > 0)
        #expect(result == hugeBase)
    }

    @Test("Constrained back-off keeps multiplying for a normal finite base interval")
    func constrainedDelayMultipliesForNormalBase() {
        let constrained = EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: true, thermalState: .nominal)
        let baseInterval: TimeInterval = 120
        let result = EnergyAwareRefreshPolicy.nextTickDelay(baseInterval: baseInterval, conditions: constrained)
        #expect(result == baseInterval * EnergyAwareRefreshPolicy.constrainedBackoffMultiplier)
        #expect(result.isFinite)
    }

    // MARK: - EnergyConditions.isConstrained

    @Test("Energy conditions are constrained when either low power or hot thermal holds")
    func constrainedConjunction() {
        #expect(EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: false, thermalState: .nominal).isConstrained == false)
        #expect(EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: false, thermalState: .fair).isConstrained == false)
        #expect(EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: true, thermalState: .nominal).isConstrained == true)
        #expect(EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: false, thermalState: .serious).isConstrained == true)
        #expect(EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: true, thermalState: .critical).isConstrained == true)
    }
}
