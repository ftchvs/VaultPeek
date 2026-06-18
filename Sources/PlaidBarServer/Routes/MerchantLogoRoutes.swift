import Foundation
import Hummingbird
import NIOCore
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Authenticated proxy + on-disk cache for merchant logos.
///
/// Plaid transaction enrichment includes a `logo_url` pointing at a Plaid CDN.
/// The app never fetches those directly — local-first means the UI only ever
/// talks to `127.0.0.1`. This route fetches the image server-side, caches it
/// under the local data directory, and serves the bytes back. Only Plaid logo
/// CDNs are allowed, and only public brand images: no user data is involved, so
/// nothing identifying leaves the machine beyond "this install fetched a logo".
struct MerchantLogoRoutes: Sendable {
    let cacheDirectory: URL
    private let session: URLSession

    private static let allowedHosts: Set<String> = [
        "plaid-merchant-logos.plaid.com",
        "plaid-counterparty-logos.plaid.com",
        "plaid-category-icons.plaid.com",
        "plaid-logo.s3.amazonaws.com",
    ]

    init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func register(with group: RouterGroup<some RequestContext>) {
        group.get("merchant-logo", use: serveLogo)
    }

    @Sendable
    func serveLogo(request: Request, context: some RequestContext) async throws -> Response {
        guard let raw = request.uri.queryParameters.get("u").map({ String($0) }),
              let logoURL = URL(string: raw),
              logoURL.scheme == "https",
              let host = logoURL.host,
              Self.allowedHosts.contains(host)
        else {
            throw HTTPError(.badRequest, message: "Unsupported logo URL")
        }

        let data = try await cachedImageData(for: logoURL)
        return Response(
            status: .ok,
            headers: [.contentType: "image/png", .cacheControl: "private, max-age=86400"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    private func cachedImageData(for url: URL) async throws -> Data {
        let file = cacheDirectory.appendingPathComponent(Self.cacheKey(for: url.absoluteString))
        if let cached = try? Data(contentsOf: file), !cached.isEmpty {
            return cached
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty
        else {
            throw HTTPError(.notFound, message: "Logo unavailable")
        }

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }

    /// Deterministic, dependency-free FNV-1a hash of the URL for a cache
    /// filename (avoids unsafe characters and stays well under path limits).
    private static func cacheKey(for url: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in url.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16) + ".img"
    }
}
