import Foundation

public enum UserFacingError {
    public static func sanitizedDetail(
        from message: String?,
        maxLength: Int = 220
    ) -> String? {
        guard let message else { return nil }

        var sanitized = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitized.isEmpty else { return nil }

        sanitized = sanitized
            .redacting(pattern: #"(?i)["']?\b(authorization)\b["']?\s*[:=]\s*["']?Bearer\s+[^"',}\s]+"#, template: "$1: Bearer [redacted]")
            .redacting(pattern: #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{12,}\b"#, template: "Bearer [redacted]")
            .redacting(pattern: #"(?i)\b(access|public|link|processor)-(sandbox|development|production)-[A-Za-z0-9_-]{8,}\b"#, template: "[redacted-token]")
            .redacting(pattern: #"(?i)["']?\b(access[-_ ]?token|public[-_ ]?token|link[-_ ]?token|processor[-_ ]?token|client[-_ ]?id|client[-_ ]?secret|secret)\b["']?\s*[:=]\s*["']?[^"',}\s]+"#, template: "$1: [redacted]")
            .redacting(pattern: #"(?i)(["']?\b(item_id|item_ids|account_id|account_ids|transaction_id|transaction_ids|txn_id|txn_ids|institution_id|institution_ids|request_id|cursor|cursor_id|link_session_id|transfer_id)\b["']?\s*[:=]\s*)\[[^\]]*\]"#, template: "$1[redacted-id]")
            .redacting(pattern: #"(?i)(["']?\b(item_id|item_ids|account_id|account_ids|transaction_id|transaction_ids|txn_id|txn_ids|institution_id|institution_ids|request_id|cursor|cursor_id|link_session_id|transfer_id)\b["']?\s*[:=]\s*)(["']?)[^"',}\]\[\s&]+(["']?)"#, template: "$1$3[redacted-id]$4")
            .redacting(pattern: #"(?i)\b(access|public|link|processor|item|account|transaction|txn|ins)_[A-Za-z0-9_-]{8,}\b"#, template: "[redacted-id]")

        sanitized = sanitized.removingStackTraceDetails()

        guard sanitized.count > maxLength else { return sanitized }
        return "\(sanitized.prefix(maxLength))..."
    }
}

private extension String {
    func redacting(pattern: String, template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return self
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        return expression.stringByReplacingMatches(
            in: self,
            options: [],
            range: range,
            withTemplate: template
        )
    }

    func removingStackTraceDetails() -> String {
        let stackMarkers = [
            " stack trace:",
            " traceback ",
            " at sources/",
            " at /",
            ".swift:"
        ]
        let lowercased = lowercased()

        guard let marker = stackMarkers.compactMap({ lowercased.range(of: $0) }).min(by: {
            $0.lowerBound < $1.lowerBound
        }) else {
            return self
        }

        let prefix = self[..<marker.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? "A local PlaidBar error occurred. Check the server logs for details." : String(prefix)
    }
}
