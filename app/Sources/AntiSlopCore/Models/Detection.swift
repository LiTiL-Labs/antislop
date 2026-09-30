import Foundation

/// What a session asks the provider for. Both use the same request data; only
/// the internal instructions and the response contract differ.
public enum SessionMode: String, Equatable, Sendable {
    /// Propose an editable replacement for the selection.
    case rewrite
    /// Point out slop patterns in the selection. Never proposes or applies text.
    case detect
}

/// One flagged passage. `quote` is an exact substring of the selection, so the
/// panel only ever shows text the writer actually selected.
public struct SlopFinding: Equatable, Sendable {
    public let quote: String
    public let issue: String
}

/// The only object a provider may return in detection mode. Pattern findings
/// about the writing itself; there is deliberately no authorship score.
public struct DetectionResponse: Equatable, Sendable {
    public let summary: String
    public let findings: [SlopFinding]
    /// Findings the model returned whose quote is not in the selection. They are
    /// dropped, never shown; the count is kept for diagnostics only.
    public let droppedFindings: Int
}

public struct ProviderDetection: Sendable {
    public let response: DetectionResponse
    public let receipt: ProviderReceipt
}

/// Host-side enforcement of the detection contract. Like `ResponseValidator`,
/// anything other than exactly one object of the expected shape is rejected.
public enum DetectionValidator {
    public static let maxFindings = 12
    public static let quoteLimit = 400
    public static let issueLimit = 200
    static let allowedKeys: Set<String> = ["summary", "findings"]
    static let findingKeys: Set<String> = ["quote", "issue"]

    public static func validate(jsonText: String, originalSelection: String) -> Result<DetectionResponse, ResponseValidationError> {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return .failure(.notJSON) }
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return .failure(trimmed.hasPrefix("{") ? .notJSON : .notSingleObject)
        }
        guard let object = parsed as? [String: Any] else { return .failure(.notSingleObject) }
        return validate(object: object, originalSelection: originalSelection)
    }

    public static func validate(object: [String: Any], originalSelection: String) -> Result<DetectionResponse, ResponseValidationError> {
        for key in object.keys.sorted() where !allowedKeys.contains(key) {
            return .failure(.unexpectedProperty(key))
        }
        for key in ["summary", "findings"] where object[key] == nil {
            return .failure(.missingProperty(key))
        }
        guard let summary = object["summary"] as? String else { return .failure(.wrongType("summary")) }
        guard let rawFindings = object["findings"] as? [Any] else { return .failure(.wrongType("findings")) }
        if summary.isBlank { return .failure(.empty("summary")) }
        if summary.codePointCount > Limits.intent { return .failure(.tooLong("summary")) }
        if rawFindings.count > maxFindings { return .failure(.tooLong("findings")) }

        var findings: [SlopFinding] = []
        var dropped = 0
        for raw in rawFindings {
            guard let f = raw as? [String: Any] else { return .failure(.wrongType("finding")) }
            for key in f.keys.sorted() where !findingKeys.contains(key) {
                return .failure(.unexpectedProperty("finding.\(key)"))
            }
            guard let quote = f["quote"] as? String else { return .failure(.wrongType("finding.quote")) }
            guard let issue = f["issue"] as? String else { return .failure(.wrongType("finding.issue")) }
            if issue.isBlank { return .failure(.empty("finding.issue")) }
            if issue.codePointCount > issueLimit || quote.codePointCount > quoteLimit {
                return .failure(.tooLong("finding"))
            }
            // Only text the writer selected may be shown back as a quote.
            guard !quote.isBlank, originalSelection.contains(quote) else {
                dropped += 1
                continue
            }
            if findings.contains(where: { $0.quote == quote && $0.issue == issue }) { continue }
            findings.append(SlopFinding(quote: quote, issue: issue))
        }
        return .success(DetectionResponse(summary: summary, findings: findings, droppedFindings: dropped))
    }

    /// Wire schema handed to provider runtimes; limits are enforced in `validate`.
    public static let providerWireSchema: String = """
    {"type":"object","additionalProperties":false,"properties":{"summary":{"type":"string"},"findings":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"quote":{"type":"string"},"issue":{"type":"string"}},"required":["quote","issue"]}}},"required":["summary","findings"]}
    """
}
