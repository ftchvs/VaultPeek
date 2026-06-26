import SwiftUI

/// A lightweight placeholder shown while the launch handshake is still loading
/// transactions (AND-582). Redacted rows convey "content is coming" without
/// implying real data; the rows are decorative and hidden from VoiceOver, which
/// reads the single status label instead.
struct TransactionsLoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.rowVertical) {
            ForEach(0..<8, id: \.self) { _ in
                skeletonRow
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        // Reuse the shared SkeletonPulse (AND-664 #3) instead of a hand-rolled
        // build-time `reduceMotion` read; this also makes the pulse react to a
        // runtime Reduce-Motion change via the modifier's `onChange`.
        .modifier(SkeletonPulse())
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading transactions")
    }

    private var skeletonRow: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(.quaternary)
                .frame(width: Sizing.iconInline + 8, height: Sizing.iconInline + 8)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(.quaternary)
                    .frame(width: 180, height: 10)
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(.quinary)
                    .frame(width: 90, height: 8)
            }
            Spacer()
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(.quaternary)
                .frame(width: 64, height: 10)
        }
    }
}
