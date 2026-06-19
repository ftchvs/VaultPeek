import Foundation

/// Pure parsing of a single `server.conf` line.
///
/// Mirrors the shell-ish syntax the server file uses: comments (`#`), blank
/// lines, an optional `export ` prefix, and `KEY=value` pairs whose value may be
/// wrapped in matching single or double quotes. This is the single source of
/// truth shared by the app (`AppState` config probes), the server
/// (`ServerConfig.loadConfigFile`), and `ServerAutoLaunchPlan`, so the syntax can
/// never silently diverge between the process that writes the file and the ones
/// that read it.
public enum ServerConfigLine {
    /// Outcome of classifying one raw line.
    public enum ParseResult: Equatable, Sendable {
        /// A blank line or a `#` comment — skip it.
        case ignored
        /// A well-formed `KEY=value` pair (value trimmed, not yet unquoted).
        case pair(key: String, value: String)
        /// A line that carries content but is not a valid pair (no `=`, or an
        /// empty key). Lenient readers skip it; strict readers (the server) treat
        /// it as a hard error.
        case malformed
    }

    /// Classify one raw line into ignored / pair / malformed. Distinguishing the
    /// last two lets a strict caller reject a malformed line while still skipping
    /// blanks and comments.
    public static func classify(_ rawLine: String) -> ParseResult {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { return .ignored }

        if line.hasPrefix("export ") {
            line.removeFirst("export ".count)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let separator = line.firstIndex(of: "=") else { return .malformed }
        let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .malformed }
        let value = String(line[line.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .pair(key: key, value: value)
    }

    /// Lenient tokenizer: the `(key, value)` pair, or `nil` for a blank, comment,
    /// or malformed line. The value is trimmed but NOT unquoted — call
    /// `unquote(_:)` when you need the bare value.
    public static func parse(_ rawLine: String) -> (key: String, value: String)? {
        if case let .pair(key, value) = classify(rawLine) { return (key, value) }
        return nil
    }

    /// Strip a single layer of matching single or double quotes, if present.
    public static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}
