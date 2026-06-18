import AppKit
import SwiftUI

/// Fetches and caches merchant logos through the local server's authenticated
/// proxy (`/api/merchant-logo`). The app never reaches a logo CDN directly: the
/// server does the fetch and on-disk caching, keeping the UI localhost-only.
@MainActor
@Observable
final class MerchantLogoStore {
    private let serverClient: ServerClient
    private var images: [String: NSImage] = [:]
    private var failed: Set<String> = []
    private var inFlight: Set<String> = []

    init(serverClient: ServerClient = ServerClient()) {
        self.serverClient = serverClient
    }

    /// Cached logo for a URL, or nil if it hasn't loaded (or failed). Reading
    /// this in a view body registers the dependency, so the row re-renders once
    /// `load` populates the cache.
    func image(for logoURL: String) -> NSImage? {
        images[logoURL]
    }

    /// Loads a logo once. Idempotent: repeated calls for the same URL while it
    /// is cached, failed, or in flight are no-ops.
    func load(_ logoURL: String) async {
        guard images[logoURL] == nil, !failed.contains(logoURL), !inFlight.contains(logoURL) else { return }
        inFlight.insert(logoURL)
        defer { inFlight.remove(logoURL) }
        do {
            let data = try await serverClient.merchantLogoData(for: logoURL)
            if let image = NSImage(data: data) {
                images[logoURL] = image
            } else {
                // Invalid image bytes won't change on retry — cache as failed.
                failed.insert(logoURL)
            }
        } catch {
            // Transport / server-still-starting / 5xx: do NOT mark failed, so a
            // later `.task` retries once the local server or network recovers.
        }
    }
}

/// Leading avatar for a transaction row: the real merchant logo when available
/// (loaded via the local proxy), falling back to a tinted dot that preserves
/// the income/outflow signal.
struct MerchantLogoView: View {
    @Environment(AppState.self) private var appState
    let logoURL: String?
    let fallbackTint: Color
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let logoURL, let image = appState.merchantLogoStore.image(for: logoURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
                    .frame(width: size, height: size)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            } else {
                Circle()
                    .fill(fallbackTint)
                    .frame(width: size, height: size)
            }
        }
        .task(id: logoURL) {
            if let logoURL { await appState.merchantLogoStore.load(logoURL) }
        }
        .accessibilityHidden(true)
    }
}
