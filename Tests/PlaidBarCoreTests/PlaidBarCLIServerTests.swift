import PlaidBarCore
import Testing

@Suite("CLI server loopback safety")
struct PlaidBarCLIServerTests {
    @Test("Loopback hosts are allowed (token may be attached)")
    func loopbackAllowed() {
        #expect(PlaidBarCLIServer.isLoopback("http://127.0.0.1:8484"))
        #expect(PlaidBarCLIServer.isLoopback("http://127.0.0.1:8484/")) // trailing slash
        #expect(PlaidBarCLIServer.isLoopback("http://localhost:8484"))
        #expect(PlaidBarCLIServer.isLoopback("http://LOCALHOST:8484")) // case-insensitive
        #expect(PlaidBarCLIServer.isLoopback("http://[::1]:8484"))
        #expect(PlaidBarCLIServer.isLoopback("http://127.5.6.7:8484")) // 127.0.0.0/8
    }

    @Test("Non-loopback hosts are rejected (token must not leak)")
    func nonLoopbackRejected() {
        #expect(!PlaidBarCLIServer.isLoopback("http://192.168.1.10:8484"))
        #expect(!PlaidBarCLIServer.isLoopback("http://10.0.0.5:8484"))
        #expect(!PlaidBarCLIServer.isLoopback("https://evil.example.com"))
        #expect(!PlaidBarCLIServer.isLoopback("http://0.0.0.0:8484"))
        // A hostname that merely starts with "127." is not a loopback IP.
        #expect(!PlaidBarCLIServer.isLoopback("http://127.evil.com:8484"))
        // 127 with the wrong octet count is not a valid loopback IPv4.
        #expect(!PlaidBarCLIServer.isLoopback("http://127.0.0:8484"))
        #expect(!PlaidBarCLIServer.isLoopback("not a url"))
    }

    @Test("Known loopback-allowlist bypass vectors are rejected")
    func bypassVectorsRejected() {
        // The classic "@"-in-authority SSRF bypass: the part before "@" is
        // userinfo, so URLComponents parses the host as the remote — the token
        // must not be sent there.
        #expect(!PlaidBarCLIServer.isLoopback("http://127.0.0.1@evil.com"))
        #expect(!PlaidBarCLIServer.isLoopback("http://localhost@evil.com"))
        // A loopback label used as a subdomain prefix is not loopback.
        #expect(!PlaidBarCLIServer.isLoopback("http://127.0.0.1.evil.com:8484"))
        // Non-decimal / packed IPv4 encodings of 127.0.0.1 are not recognized.
        #expect(!PlaidBarCLIServer.isLoopback("http://0x7f.0.0.1:8484"))   // hex octet
        #expect(!PlaidBarCLIServer.isLoopback("http://0177.0.0.1:8484"))   // octal octet
        #expect(!PlaidBarCLIServer.isLoopback("http://2130706433:8484"))   // packed decimal
        // IPv4-mapped IPv6 and trailing-dot forms fail safe (rejected, not sent).
        #expect(!PlaidBarCLIServer.isLoopback("http://[::ffff:127.0.0.1]:8484"))
        #expect(!PlaidBarCLIServer.isLoopback("http://localhost.:8484"))
    }
}
