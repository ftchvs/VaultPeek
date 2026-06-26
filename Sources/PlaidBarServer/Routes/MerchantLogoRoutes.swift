import Foundation
import Hummingbird
import NIOCore
import PlaidBarCore
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

    /// Hard ceiling on a single buffered logo response. Brand logos are small
    /// PNG/SVG assets (a few KB); 2 MB leaves generous headroom while bounding
    /// the in-memory buffer so a misbehaving or compromised upstream can't pin
    /// arbitrary memory in the proxy. Enforced before streaming via advertised
    /// `Content-Length` and during streaming so a chunked or lying upstream
    /// can't grow the local buffer past the cap.
    static let maxLogoBytes = 2 * 1024 * 1024

    /// Content types we are willing to serve back. The upstream `Content-Type`
    /// is passed through when it is a recognized image type; otherwise we fall
    /// back to PNG (the historical default) so a missing/odd header never
    /// degrades a known-good Plaid asset.
    private static let allowedContentTypePrefixes = ["image/"]
    private static let fallbackContentType = "image/png"

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

        let logo = try await cachedImageData(for: logoURL)
        return Response(
            status: .ok,
            headers: [.contentType: logo.contentType, .cacheControl: "private, max-age=86400"],
            body: .init(byteBuffer: ByteBuffer(data: logo.data))
        )
    }

    /// A buffered logo plus the content type to serve it under.
    private struct CachedLogo {
        let data: Data
        let contentType: String
    }

    private func cachedImageData(for url: URL) async throws -> CachedLogo {
        let file = cacheDirectory.appendingPathComponent(Self.cacheKey(for: url.absoluteString))
        if let cached = try? Data(contentsOf: file), !cached.isEmpty {
            // Cached bytes have no stored header; sniff the type from the
            // payload, defaulting to PNG (the historical content type).
            return CachedLogo(data: cached, contentType: Self.sniffContentType(of: cached))
        }

        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw HTTPError(.notFound, message: "Logo unavailable")
        }
        // URLSession follows redirects, so an allowed Plaid URL could redirect
        // elsewhere; re-validate the FINAL host before reading any body bytes so
        // the allowlist applies to the bytes actually served.
        guard let finalHost = http.url?.host, Self.allowedHosts.contains(finalHost) else {
            throw HTTPError(.notFound, message: "Logo redirected to a disallowed host")
        }

        let advertisedContentLength = Self.advertisedContentLength(http)
        // Reject an honest oversized response before streaming the body.
        guard !Self.exceedsLogoSizeLimit(
            advertisedContentLength: advertisedContentLength,
            actualByteCount: 0
        ) else {
            throw HTTPError(.notFound, message: "Logo exceeds size limit")
        }

        var data = Data()
        data.reserveCapacity(min(advertisedContentLength ?? 0, Self.maxLogoBytes))
        for try await byte in bytes {
            guard Self.appendLogoByte(byte, to: &data) else {
                throw HTTPError(.notFound, message: "Logo exceeds size limit")
            }
        }
        guard !data.isEmpty else {
            throw HTTPError(.notFound, message: "Logo unavailable")
        }

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return CachedLogo(data: data, contentType: Self.contentType(from: http))
    }

    /// Whether a response should be rejected for exceeding ``maxLogoBytes``.
    /// `true` when either the advertised `Content-Length` or the materialized
    /// byte count is over the cap. Pure decision function, exercised directly by
    /// tests so the bound is verified without a live network fetch.
    static func exceedsLogoSizeLimit(advertisedContentLength: Int?, actualByteCount: Int) -> Bool {
        if let advertisedContentLength, advertisedContentLength > maxLogoBytes {
            return true
        }
        return actualByteCount > maxLogoBytes
    }

    /// Appends one streamed byte without letting the local logo buffer exceed
    /// ``maxLogoBytes``. Returns `false` before mutating once the buffer is full,
    /// so the caller can abort a chunked or understated response at the boundary.
    static func appendLogoByte(_ byte: UInt8, to data: inout Data) -> Bool {
        guard data.count < maxLogoBytes else {
            return false
        }
        data.append(byte)
        return true
    }

    /// Parses the upstream `Content-Length` if present and well-formed. A
    /// missing or unparseable header returns `nil` (cap then relies on the
    /// materialized byte count).
    static func advertisedContentLength(_ http: HTTPURLResponse) -> Int? {
        guard let raw = http.value(forHTTPHeaderField: "Content-Length"),
              let length = Int(raw.trimmingCharacters(in: .whitespaces)), length >= 0 else {
            return nil
        }
        return length
    }

    /// Derives the response content type from the upstream header, passing it
    /// through only when it is a recognized image type. Anything else (missing,
    /// `text/html`, etc.) falls back to PNG so a known-good asset is still served.
    static func contentType(from http: HTTPURLResponse) -> String {
        guard let raw = http.value(forHTTPHeaderField: "Content-Type") else {
            return fallbackContentType
        }
        let value = raw.split(separator: ";", maxSplits: 1).first.map { String($0) }?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard allowedContentTypePrefixes.contains(where: value.hasPrefix), !value.isEmpty else {
            return fallbackContentType
        }
        return value
    }

    /// Infers the content type of cached bytes from their magic number so a
    /// cache hit serves the same type a fresh fetch would. Covers the formats
    /// Plaid CDNs return; unknown payloads default to PNG.
    static func sniffContentType(of data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if bytes.count >= 12,
           bytes.starts(with: [0x52, 0x49, 0x46, 0x46]),
           Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
        if bytes.starts(with: [0x3C, 0x73, 0x76, 0x67]) || bytes.starts(with: [0x3C, 0x3F, 0x78, 0x6D]) {
            return "image/svg+xml"
        }
        return fallbackContentType
    }

    /// Deterministic, dependency-free FNV-1a hash of the URL for a cache
    /// filename (avoids unsafe characters and stays well under path limits).
    private static func cacheKey(for url: String) -> String {
        StableHash.hex(url) + ".img"
    }
}
