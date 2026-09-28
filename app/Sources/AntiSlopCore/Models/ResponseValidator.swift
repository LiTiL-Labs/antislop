import Foundation

public enum ResponseValidationError: Error, Equatable, Sendable {
    case notJSON
    case notSingleObject
    case unexpectedProperty(String)
    case missingProperty(String)
    case wrongType(String)
    case tooLong(String)
    case empty(String)
    case blankReplacementForSubstantiveSource

    /// Sanitized description; never contains response or source text.
    public var diagnostic: String {
        switch self {
        case .notJSON: return "response was not JSON"
        case .notSingleObject: return "response was not exactly one JSON object"
        case .unexpectedProperty(let k): return "unexpected property \(k)"
        case .missingProperty(let k): return "missing property \(k)"
        case .wrongType(let k): return "wrong type for \(k)"
        case .tooLong(let k): return "\(k) exceeds its limit"
        case .empty(let k): return "\(k) is empty"
        case .blankReplacementForSubstantiveSource: return "blank replacement for substantive source"
        }
    }
}

/// Host-side enforcement of schemas/rewrite-response.schema.json plus the
/// no-accidental-deletion rule. Provider wire schemas may be looser; this is not.
/// Never extracts JSON from surrounding prose: anything other than exactly one
/// object is rejected so the wrong text can never be applied.
public enum ResponseValidator {
    static let allowedKeys: Set<String> = ["intent", "rewritten_text", "note"]

    public static func validate(jsonText: String, originalSelection: String) -> Result<RewriteResponse, ResponseValidationError> {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return .failure(.notJSON) }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            // Prose or a code fence around an object is a wrapper, not a parse slip.
            return .failure(trimmed.hasPrefix("{") ? .notJSON : .notSingleObject)
        }
        guard let object = parsed as? [String: Any] else { return .failure(.notSingleObject) }
        return validate(object: object, originalSelection: originalSelection)
    }

    public static func validate(object: [String: Any], originalSelection: String) -> Result<RewriteResponse, ResponseValidationError> {
        for key in object.keys.sorted() where !allowedKeys.contains(key) {
            return .failure(.unexpectedProperty(key))
        }
        for key in ["intent", "rewritten_text", "note"] where object[key] == nil {
            return .failure(.missingProperty(key))
        }
        guard let intent = object["intent"] as? String else { return .failure(.wrongType("intent")) }
        guard let rewritten = object["rewritten_text"] as? String else { return .failure(.wrongType("rewritten_text")) }

        let note: String?
        if object["note"] is NSNull {
            note = nil
        } else if let n = object["note"] as? String {
            note = n
        } else {
            return .failure(.wrongType("note"))
        }

        if intent.isEmpty { return .failure(.empty("intent")) }
        if intent.codePointCount > Limits.intent { return .failure(.tooLong("intent")) }
        if rewritten.isEmpty { return .failure(.empty("rewritten_text")) }
        if rewritten.codePointCount > Limits.responseText { return .failure(.tooLong("rewritten_text")) }
        if let note {
            if note.isEmpty { return .failure(.empty("note")) }
            if note.codePointCount > Limits.note { return .failure(.tooLong("note")) }
        }
        if rewritten.isBlank && !originalSelection.isBlank {
            return .failure(.blankReplacementForSubstantiveSource)
        }
        return .success(RewriteResponse(intent: intent, rewrittenText: rewritten, note: note))
    }

    /// Wire schema handed to provider runtimes. Strict-mode structured output
    /// subsets reject some keywords (e.g. length bounds), so limits live in
    /// `validate` instead; nothing here weakens host validation.
    public static let providerWireSchema: String = """
    {"type":"object","additionalProperties":false,"properties":{"intent":{"type":"string"},"rewritten_text":{"type":"string"},"note":{"type":["string","null"]}},"required":["intent","rewritten_text","note"]}
    """
}
