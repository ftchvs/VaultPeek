import PlaidBarCore
import SwiftUI

/// Full-surface gate shown when App Lock is engaged (LOCKED, not just masked).
/// It paints an opaque material over the entire surface so no real value,
/// account, or institution name behind it can be read, and offers a single
/// Unlock action that re-prompts for authentication. Distinct from Privacy
/// Mask, which only dots currency and leaves content visible (AND-462).
///
/// Shared by **both** local UI surfaces so App Lock gating is identical across
/// them (ADR-001 Epic 10 / AND-588 security parity):
/// - the menu-bar popover + its detached host (`MainPopover`), and
/// - the window-first primary workspace (`AppShellView`).
///
/// Because the host window can render a clear/non-opaque root (the popover's
/// detached host and the window-first shell both paint glass chrome), the gate
/// must obscure on its own rather than rely on the host being opaque.
struct AppLockedGateView: View {
    let message: String
    let reduceMotion: Bool
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            // Opaque backdrop: the detached window renders a clear root, so the
            // gate cannot rely on the host being opaque — it must obscure on its
            // own. `.bar` material over the window background fully hides content.
            Rectangle()
                .fill(.background)
                .overlay(.bar)
                .ignoresSafeArea()

            VStack(spacing: Spacing.md) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("VaultPeek Locked")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppearanceTextColors.primary)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)

                Button(action: onUnlock) {
                    Label("Unlock", systemImage: "lock.open.fill")
                        .frame(minWidth: 120)
                }
                // The primary unlock CTA uses prominent Liquid Glass (AND-511):
                // it is the highest-signal action on the lock surface and reads
                // as a tinted glass capsule consistent with the glass chrome.
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("VaultPeek is locked. \(message)")
        .accessibilityAddTraits(.isModal)
    }
}
