import Foundation

// Model-visible contracts from schemas/*.schema.json (version 0.2).
// Swift's synthesized Codable omits nil optionals, but the schemas require
// nullable keys to be present, so encoding is written out explicitly.

public enum ContractVersion {
    public static let schema = "0.3"
    public static let prompt = "0.3"
}

public enum SelectionKind: String, Codable, CaseIterable, Sendable {
    case prose, code, mixed, unknown
}

public enum ContextBoundary: String, Codable, Sendable {
    case knownExcerpt = "known_excerpt"
    case documentBoundary = "document_boundary"
    case unavailable
}

/// One side of the nearby context. Invariants (schemas/README.md):
/// `unavailable` has nil text, `document_boundary` has "", `known_excerpt` has text.
public struct ContextSide: Equatable, Sendable {
    public let text: String?
    public let boundary: ContextBoundary

    public static let unavailable = ContextSide(uncheckedText: nil, boundary: .unavailable)
    public static let documentBoundary = ContextSide(uncheckedText: "", boundary: .documentBoundary)

    public static func excerpt(_ text: String) -> ContextSide {
        // An empty excerpt is not evidence of a document edge; callers decide
        // boundaries, so an empty known excerpt is represented as unavailable.
        text.isEmpty ? .unavailable : ContextSide(uncheckedText: text, boundary: .knownExcerpt)
    }

    init(uncheckedText: String?, boundary: ContextBoundary) {
        self.text = uncheckedText
        self.boundary = boundary
    }

    public var isConsistent: Bool {
        switch boundary {
        case .unavailable: return text == nil
        case .documentBoundary: return text == ""
        case .knownExcerpt: return (text?.isEmpty == false)
        }
    }
}

extension ContextSide: Codable {
    enum CodingKeys: String, CodingKey { case text, boundary }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let text = try c.decodeIfPresent(String.self, forKey: .text)
        let boundary = try c.decode(ContextBoundary.self, forKey: .boundary)
        self.init(uncheckedText: text, boundary: boundary)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let text { try c.encode(text, forKey: .text) } else { try c.encodeNil(forKey: .text) }
        try c.encode(boundary, forKey: .boundary)
    }
}

public struct NearbyContext: Codable, Equatable, Sendable {
    public var before: ContextSide
    public var after: ContextSide
    public init(before: ContextSide, after: ContextSide) {
        self.before = before
        self.after = after
    }
    public static let unavailable = NearbyContext(before: .unavailable, after: .unavailable)
}

public struct SourceHint: Equatable, Sendable {
    public var appName: String?
    public var documentTitle: String?
    public var contentTypeHint: String?
    public init(appName: String? = nil, documentTitle: String? = nil, contentTypeHint: String? = nil) {
        self.appName = appName
        self.documentTitle = documentTitle
        self.contentTypeHint = contentTypeHint
    }
    public static let none = SourceHint()
}

extension SourceHint: Codable {
    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case documentTitle = "document_title"
        case contentTypeHint = "content_type_hint"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        documentTitle = try c.decodeIfPresent(String.self, forKey: .documentTitle)
        contentTypeHint = try c.decodeIfPresent(String.self, forKey: .contentTypeHint)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeNullable(appName, forKey: .appName)
        try c.encodeNullable(documentTitle, forKey: .documentTitle)
        try c.encodeNullable(contentTypeHint, forKey: .contentTypeHint)
    }
}

public enum SentenceComplexity: String, Codable, CaseIterable, Sendable {
    case caveman, plain, balanced, polished, lawyer

    public var displayName: String { rawValue.capitalized }
    public var guidance: String {
        switch self {
        case .caveman: return "Use the shortest clear sentences and everyday words. Keep complete, grammatical thoughts; never caricature the writer or omit conditions."
        case .plain: return "Use plain language and mostly short sentences, with one main idea per sentence where the logical relationships survive."
        case .balanced: return "Use natural sentence variety and familiar wording; keep subordinate clauses when they clarify a relationship."
        case .polished: return "Use fluent, nuanced sentences and a professional register. Allow varied clauses without ornamental vocabulary or filler."
        case .lawyer: return "Use precise, formal sentences with carefully connected clauses and explicit qualifications. Complexity must serve accuracy; never add legalese, obligations, citations or legal advice."
        }
    }
}

public struct WritingPreferences: Codable, Equatable, Sendable {
    public var sentenceComplexity: SentenceComplexity
    public init(sentenceComplexity: SentenceComplexity = .balanced) {
        self.sentenceComplexity = sentenceComplexity
    }
    public static let defaults = WritingPreferences()
    enum CodingKeys: String, CodingKey { case sentenceComplexity = "sentence_complexity" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sentenceComplexity = try c.decodeIfPresent(SentenceComplexity.self, forKey: .sentenceComplexity) ?? .balanced
    }
}

public struct StyleGuide: Codable, Equatable, Sendable {
    public var label: String
    public var text: String
    public init(label: String, text: String) {
        self.label = label
        self.text = text
    }
}

/// Fixed editorial-standard identifier in request receipts, not a user-selectable profile.
public enum StyleProfileID: String, Codable, CaseIterable, Sendable {
    case litil
    public var revision: String { ContractVersion.prompt }
}

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode = "claude-code"

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        }
    }

    public var accountLabel: String {
        switch self {
        case .codex: return "ChatGPT account"
        case .claudeCode: return "Claude account"
        }
    }
}

/// Model-visible request data (schemas/rewrite-request.schema.json). Carries no
/// native handles, process identifiers, clipboard content or session identity.
public struct RewriteRequest: Equatable, Sendable {
    public var schemaVersion: String = ContractVersion.schema
    public var promptVersion: String = ContractVersion.prompt
    public var selectedText: String
    public var selectionKind: SelectionKind
    public var nearbyContext: NearbyContext
    public var sourceHint: SourceHint
    public var userSettings: WritingPreferences
    public var styleGuide: StyleGuide?
    public var styleProfileID: StyleProfileID
    public var profileRevision: String

    public init(
        selectedText: String,
        selectionKind: SelectionKind,
        nearbyContext: NearbyContext,
        sourceHint: SourceHint,
        userSettings: WritingPreferences,
        styleGuide: StyleGuide?,
        styleProfileID: StyleProfileID
    ) {
        self.selectedText = selectedText
        self.selectionKind = selectionKind
        self.nearbyContext = nearbyContext
        self.sourceHint = sourceHint
        self.userSettings = userSettings
        self.styleGuide = styleGuide
        self.styleProfileID = styleProfileID
        self.profileRevision = styleProfileID.revision
    }
}

extension RewriteRequest: Codable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case promptVersion = "prompt_version"
        case selectedText = "selected_text"
        case selectionKind = "selection_kind"
        case nearbyContext = "nearby_context"
        case sourceHint = "source_hint"
        case userSettings = "user_settings"
        case styleGuide = "style_guide"
        case styleProfileID = "style_profile_id"
        case profileRevision = "profile_revision"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = ContractVersion.schema
        promptVersion = ContractVersion.prompt
        selectedText = try c.decode(String.self, forKey: .selectedText)
        selectionKind = try c.decode(SelectionKind.self, forKey: .selectionKind)
        nearbyContext = try c.decode(NearbyContext.self, forKey: .nearbyContext)
        sourceHint = try c.decode(SourceHint.self, forKey: .sourceHint)
        userSettings = try c.decode(WritingPreferences.self, forKey: .userSettings)
        styleGuide = try c.decodeIfPresent(StyleGuide.self, forKey: .styleGuide)
        styleProfileID = .litil
        profileRevision = StyleProfileID.litil.revision
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(promptVersion, forKey: .promptVersion)
        try c.encode(selectedText, forKey: .selectedText)
        try c.encode(selectionKind, forKey: .selectionKind)
        try c.encode(nearbyContext, forKey: .nearbyContext)
        try c.encode(sourceHint, forKey: .sourceHint)
        try c.encode(userSettings, forKey: .userSettings)
        try c.encodeNullable(styleGuide, forKey: .styleGuide)
        try c.encode(styleProfileID, forKey: .styleProfileID)
        try c.encode(profileRevision, forKey: .profileRevision)
    }
}

/// The only object a provider may return (schemas/rewrite-response.schema.json).
/// Instances are produced by `ResponseValidator`, never by decoding directly.
public struct RewriteResponse: Equatable, Sendable {
    public let intent: String
    public let rewrittenText: String
    public let note: String?

    init(intent: String, rewrittenText: String, note: String?) {
        self.intent = intent
        self.rewrittenText = rewrittenText
        self.note = note
    }
}

extension KeyedEncodingContainer {
    mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) }
    }
}

public enum ContractJSON {
    /// Deterministic encoder for model-visible data: sorted keys, no escaped
    /// slashes (so URLs reach the model verbatim), pretty-printed for readability.
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return e
    }

    public static func encodeString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

extension String {
    /// Length as JSON Schema counts it (Unicode code points).
    public var codePointCount: Int { unicodeScalars.count }

    public var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
