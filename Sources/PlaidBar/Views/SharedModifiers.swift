import SwiftUI
import PlaidBarCore

// MARK: - Hover Highlight

struct HoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.04) : .clear)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

// MARK: - Refresh Icon (smooth spin via repeatForever)

struct RefreshIcon: View {
    let isLoading: Bool
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(rotation))
            .onChange(of: isLoading) { _, loading in
                if loading {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                } else {
                    withAnimation(.linear(duration: 0.3)) {
                        rotation = 0
                    }
                }
            }
            .onAppear {
                if isLoading {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            }
    }
}

// MARK: - Secondary Empty State

struct SecondaryUnavailableView: View {
    let presentation: SecondaryContentUnavailableState
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(presentation.title, systemImage: presentation.iconName)
        } description: {
            Text(presentation.detail)
        } actions: {
            Button(action: action) {
                Label(presentation.actionTitle, systemImage: presentation.actionIconName)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
    }
}
