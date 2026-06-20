import SwiftUI

/// A lightweight placeholder shown while the launch handshake is still loading
/// transactions (AND-582). Redacted rows convey "content is coming" without
/// implying real data; the rows are decorative and hidden from VoiceOver, which
/// reads the single status label instead.
struct TransactionsLoadingSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.rowVertical) {
            ForEach(0..<8, id: \.self) { _ in
                skeletonRow
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .opacity(reduceMotion ? 0.6 : (shimmer ? 0.4 : 0.7))
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
            value: shimmer
        )
        .onAppear { shimmer = true }
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
