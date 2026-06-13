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
}
