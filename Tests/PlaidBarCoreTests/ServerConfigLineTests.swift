import Foundation
@testable import PlaidBarCore
import Testing

@Suite("ServerConfigLine Tests")
struct ServerConfigLineTests {
    // MARK: - classify

    @Test("classify: blank and comment lines are ignored")
    func classifyIgnored() {
        #expect(ServerConfigLine.classify("") == .ignored)
        #expect(ServerConfigLine.classify("   \t ") == .ignored)
        #expect(ServerConfigLine.classify("# a comment") == .ignored)
        #expect(ServerConfigLine.classify("   # indented comment") == .ignored)
    }

    @Test("classify: well-formed pairs, with trimming and optional export prefix")
    func classifyPairs() {
        #expect(ServerConfigLine.classify("FOO=bar") == .pair(key: "FOO", value: "bar"))
        #expect(ServerConfigLine.classify("export FOO=bar") == .pair(key: "FOO", value: "bar"))
        // Surrounding and inner whitespace around key/value is trimmed.
        #expect(ServerConfigLine.classify("  export   FOO = bar  ") == .pair(key: "FOO", value: "bar"))
        // An empty value is still a valid pair.
        #expect(ServerConfigLine.classify("FOO=") == .pair(key: "FOO", value: ""))
        // Only the FIRST '=' splits; later ones belong to the value.
        #expect(ServerConfigLine.classify("FOO=a=b") == .pair(key: "FOO", value: "a=b"))
        // Inner spaces in the value are preserved; quotes are NOT stripped here.
        #expect(ServerConfigLine.classify("FOO=\"a b\"") == .pair(key: "FOO", value: "\"a b\""))
    }

    @Test("classify: content without a valid key=value is malformed")
    func classifyMalformed() {
        #expect(ServerConfigLine.classify("FOO") == .malformed) // no '='
        #expect(ServerConfigLine.classify("=bar") == .malformed) // empty key
        #expect(ServerConfigLine.classify("   =bar") == .malformed)
        #expect(ServerConfigLine.classify("export ") == .malformed) // export prefix, nothing after
        #expect(ServerConfigLine.classify("export") == .malformed) // bare word, no '='
    }

    // MARK: - parse (lenient convenience)

    @Test("parse: returns the pair, or nil for ignored/malformed")
    func parseLenient() {
        let pair = ServerConfigLine.parse("export KEY=value")
        #expect(pair?.key == "KEY")
        #expect(pair?.value == "value")
        #expect(ServerConfigLine.parse("# comment") == nil)
        #expect(ServerConfigLine.parse("") == nil)
        #expect(ServerConfigLine.parse("NOEQUALS") == nil)
        #expect(ServerConfigLine.parse("=novalue") == nil)
    }

    // MARK: - unquote

    @Test("unquote: strips one layer of matching quotes only")
    func unquote() {
        #expect(ServerConfigLine.unquote("\"hello\"") == "hello")
        #expect(ServerConfigLine.unquote("'hello'") == "hello")
        #expect(ServerConfigLine.unquote("bare") == "bare")
        #expect(ServerConfigLine.unquote("\"\"") == "") // empty quoted value
        // Mismatched / single / unbalanced quotes are left untouched.
        #expect(ServerConfigLine.unquote("\"oops'") == "\"oops'")
        #expect(ServerConfigLine.unquote("\"") == "\"")
        #expect(ServerConfigLine.unquote("") == "")
        // Only the outermost layer is removed.
        #expect(ServerConfigLine.unquote("\"'nested'\"") == "'nested'")
    }
}
