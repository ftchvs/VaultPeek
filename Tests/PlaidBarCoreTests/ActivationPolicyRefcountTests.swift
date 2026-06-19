import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Activation-policy refcount (ADR-001 R-01 / AND-620)")
struct ActivationPolicyRefcountTests {
    typealias Policy = ActivationPolicyRefcount.ActivationPolicy

    // MARK: - Single-surface cycle: accessory → regular → accessory

    @Test("One window open then close round-trips .accessory → .regular → .accessory")
    func singleSurfaceCycle() {
        var refcount = ActivationPolicyRefcount()
        var policy: Policy = .accessory

        // Window opens: elevate.
        let onOpen = refcount.request(currentPolicy: policy)
        #expect(onOpen == .regular)
        policy = onOpen ?? policy
        #expect(policy == .regular)
        #expect(refcount.requestCount == 1)

        // Window closes: drop back to the captured baseline.
        let onClose = refcount.release(currentPolicy: policy)
        #expect(onClose == .accessory)
        policy = onClose ?? policy
        #expect(policy == .accessory)
        #expect(refcount.requestCount == 0)
        // No leaked baseline once balanced.
        #expect(refcount.baseline == nil)
    }

    @Test("A balanced open/close leaves the refcount equal to a fresh instance")
    func balancedCycleLeavesNoState() {
        var refcount = ActivationPolicyRefcount()
        _ = refcount.request(currentPolicy: .accessory)
        _ = refcount.release(currentPolicy: .regular)
        #expect(refcount == ActivationPolicyRefcount())
    }

    // MARK: - Multi-surface refcount: last close wins

    @Test("Two surfaces: closing one does not prematurely drop to .accessory")
    func twoSurfacesLastCloseDropsPolicy() {
        var refcount = ActivationPolicyRefcount()
        var policy: Policy = .accessory

        // First surface (e.g. the primary Window) opens: elevate.
        policy = refcount.request(currentPolicy: policy) ?? policy
        #expect(policy == .regular)

        // Second surface (e.g. a legacy AppKit window or Settings) opens while
        // already .regular: no change needed, but the count rises.
        let secondOpen = refcount.request(currentPolicy: policy)
        #expect(secondOpen == nil)
        #expect(policy == .regular)
        #expect(refcount.requestCount == 2)

        // First surface closes: still one outstanding request, stay .regular.
        let firstClose = refcount.release(currentPolicy: policy)
        #expect(firstClose == nil)
        #expect(policy == .regular)
        #expect(refcount.requestCount == 1)

        // Last surface closes: now drop to .accessory.
        let lastClose = refcount.release(currentPolicy: policy)
        #expect(lastClose == .accessory)
        policy = lastClose ?? policy
        #expect(policy == .accessory)
        #expect(refcount.requestCount == 0)
        #expect(refcount.baseline == nil)
    }

    @Test("Interleaved open/close across surfaces never leaks .regular")
    func interleavedSurfacesNeverLeakRegular() {
        var refcount = ActivationPolicyRefcount()
        var policy: Policy = .accessory

        // open A, open B, close A, open C, close B, close C
        policy = refcount.request(currentPolicy: policy) ?? policy // A → regular
        policy = refcount.request(currentPolicy: policy) ?? policy // B
        policy = refcount.release(currentPolicy: policy) ?? policy // close A
        policy = refcount.request(currentPolicy: policy) ?? policy // C
        policy = refcount.release(currentPolicy: policy) ?? policy // close B
        #expect(policy == .regular) // C still open

        policy = refcount.release(currentPolicy: policy) ?? policy // close C
        #expect(policy == .accessory)
        #expect(refcount.requestCount == 0)
        #expect(refcount.baseline == nil)
    }

    // MARK: - Baseline preservation (launch flag set .regular intentionally)

    @Test("A pre-elevated .regular baseline is preserved across the cycle")
    func preElevatedBaselinePreserved() {
        var refcount = ActivationPolicyRefcount()
        // Launch flag (e.g. --regular-activation) already set .regular before any
        // surface requested elevation.
        var policy: Policy = .regular

        // Window opens while already .regular: no change, but baseline captured.
        let onOpen = refcount.request(currentPolicy: policy)
        #expect(onOpen == nil)
        #expect(refcount.baseline == .regular)

        // Window closes: restore the captured .regular baseline — do NOT strip the
        // intentional Dock presence down to .accessory.
        let onClose = refcount.release(currentPolicy: policy)
        #expect(onClose == nil) // already .regular, no change needed
        policy = onClose ?? policy
        #expect(policy == .regular)
        #expect(refcount.requestCount == 0)
    }

    @Test("Baseline is captured only on the first of several requests")
    func baselineCapturedOnFirstRequestOnly() {
        var refcount = ActivationPolicyRefcount()
        _ = refcount.request(currentPolicy: .accessory) // first → baseline = .accessory
        // A second request observing .regular must NOT overwrite the baseline.
        _ = refcount.request(currentPolicy: .regular)
        #expect(refcount.baseline == .accessory)

        _ = refcount.release(currentPolicy: .regular) // still 1 outstanding
        let last = refcount.release(currentPolicy: .regular) // last → restore .accessory
        #expect(last == .accessory)
    }

    // MARK: - Over-release safety

    @Test("Releasing past zero is a no-op and cannot wedge the policy")
    func releasePastZeroIsNoOp() {
        var refcount = ActivationPolicyRefcount()
        // Release with nothing outstanding.
        #expect(refcount.release(currentPolicy: .accessory) == nil)
        #expect(refcount.requestCount == 0)

        // Balanced cycle, then an extra spurious release.
        _ = refcount.request(currentPolicy: .accessory)
        _ = refcount.release(currentPolicy: .regular)
        #expect(refcount.release(currentPolicy: .accessory) == nil)
        #expect(refcount.requestCount == 0)
        #expect(refcount.baseline == nil)
    }

    // MARK: - Feature-flag toggle simulation

    @Test("Flag toggle off→on→off: opening then closing the window leaves no leaked policy")
    func flagToggleCycleLeavesNoLeak() {
        // Models AND-620's flag-toggle acceptance: with the flag OFF the window
        // never opens, so the refcount is never touched and the policy stays
        // .accessory; flipping the flag ON and opening/closing the window must
        // round-trip cleanly back to .accessory with no leaked activation state.
        var refcount = ActivationPolicyRefcount()
        var policy: Policy = .accessory

        // Flag OFF — window never opens. No requests; policy unchanged.
        #expect(refcount.requestCount == 0)
        #expect(policy == .accessory)

        // Flag flipped ON — window opens.
        policy = refcount.request(currentPolicy: policy) ?? policy
        #expect(policy == .regular)

        // Window closes (user closes it, or flips the flag back OFF).
        policy = refcount.release(currentPolicy: policy) ?? policy
        #expect(policy == .accessory)

        // Flag OFF again — fully clean, identical to the never-opened state.
        #expect(refcount == ActivationPolicyRefcount())
    }

    @Test("Repeated open/close cycles each round-trip to .accessory")
    func repeatedCyclesAreStable() {
        var refcount = ActivationPolicyRefcount()
        var policy: Policy = .accessory
        for _ in 0 ..< 5 {
            policy = refcount.request(currentPolicy: policy) ?? policy
            #expect(policy == .regular)
            policy = refcount.release(currentPolicy: policy) ?? policy
            #expect(policy == .accessory)
            #expect(refcount.requestCount == 0)
            #expect(refcount.baseline == nil)
        }
    }
}
