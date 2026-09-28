import Foundation

/// A UTF-16 range, the unit macOS accessibility uses for text ranges.
public struct TextRange: Equatable, Hashable, Sendable {
    public var location: Int
    public var length: Int
    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
    public var end: Int { location + length }
}

/// What capture produced for the model: the exact selection and bounded,
/// explicitly-labelled surroundings.
public struct CapturedText: Equatable, Sendable {
    public let selectedText: String
    public let selectionKind: SelectionKind
    public let context: NearbyContext
    public let sourceHint: SourceHint

    public init(selectedText: String, selectionKind: SelectionKind, context: NearbyContext, sourceHint: SourceHint) {
        self.selectedText = selectedText
        self.selectionKind = selectionKind
        self.context = context
        self.sourceHint = sourceHint
    }
}

public enum CaptureRefusal: Error, Equatable, Sendable {
    case noSelection
    case secureField
    case notText
    case tooLong(count: Int)
    case accessibilityNotTrusted
    case unreadable

    /// Short, concrete, non-blaming feedback (UX.md "Feedback tone").
    public var message: String {
        switch self {
        case .noSelection: return "Select some text first."
        case .secureField: return "Anti-slop doesn't read password or secure fields."
        case .notText: return "That selection isn't editable text."
        case .tooLong(let n):
            return "That selection is \(n.grouped()) characters. Select less than \(Limits.selectedText.grouped()) characters."
        case .accessibilityNotTrusted: return "Allow Anti-slop in Accessibility settings to read the selection."
        case .unreadable: return "Couldn't read the selected text in this app."
        }
    }
}

extension Int {
    func grouped() -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: self)) ?? String(self)
    }
}

public enum ContextBuilder {
    /// Build the model-visible capture.
    /// - Parameters:
    ///   - selectedText: the exact selection as reported by the source.
    ///   - fullText: the control's text, if the source exposes it.
    ///   - selectedRange: UTF-16 selection range within `fullText`, if exposed.
    ///   - fullTextIsComplete: whether `fullText` is known to be the control's
    ///     entire value (only then is an edge a real document boundary).
    public static func build(
        selectedText: String,
        fullText: String?,
        selectedRange: TextRange?,
        fullTextIsComplete: Bool,
        sourceHint: SourceHint
    ) -> Result<CapturedText, CaptureRefusal> {
        if selectedText.isEmpty || selectedText.isBlank { return .failure(.noSelection) }
        let n = selectedText.codePointCount
        if n > Limits.selectedText { return .failure(.tooLong(count: n)) }

        var context = NearbyContext.unavailable
        if let fullText, let range = selectedRange,
           let split = split(fullText, at: range), split.selection == selectedText {
            context.before = beforeSide(split.before, isComplete: fullTextIsComplete)
            context.after = afterSide(split.after, isComplete: fullTextIsComplete)
        }
        // A mismatch between the reported range and selected text leaves context
        // unavailable: conservative selection-only editing is valid.

        return .success(CapturedText(
            selectedText: selectedText,
            selectionKind: classify(selectedText),
            context: context,
            sourceHint: sourceHint
        ))
    }

    /// Split text around a UTF-16 range; nil if out of bounds or not on scalar boundaries.
    public static func split(_ text: String, at range: TextRange) -> (before: String, selection: String, after: String)? {
        let u = text.utf16
        guard range.location >= 0, range.length >= 0, range.end <= u.count else { return nil }
        let s = u.index(u.startIndex, offsetBy: range.location)
        let e = u.index(s, offsetBy: range.length)
        guard s.samePosition(in: text.unicodeScalars) != nil, e.samePosition(in: text.unicodeScalars) != nil else { return nil }
        return (String(text[..<s]), String(text[s..<e]), String(text[e...]))
    }

    static func beforeSide(_ before: String, isComplete: Bool) -> ContextSide {
        if before.isEmpty { return isComplete ? .documentBoundary : .unavailable }
        return .excerpt(trimFarStart(before, limit: Limits.contextPerSide))
    }

    static func afterSide(_ after: String, isComplete: Bool) -> ContextSide {
        if after.isEmpty { return isComplete ? .documentBoundary : .unavailable }
        return .excerpt(trimFarEnd(after, limit: Limits.contextPerSide))
    }

    /// Keep the end of `text` (adjacent to the selection) exactly; cut the far
    /// start at a paragraph, then word, boundary.
    static func trimFarStart(_ text: String, limit: Int) -> String {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count > limit else { return text }
        let window = Array(scalars.suffix(limit))
        let searchSpan = min(window.count, limit / 2)
        if let nl = window.prefix(searchSpan).firstIndex(where: { $0 == "\n" }), nl + 1 < window.count {
            return String(String.UnicodeScalarView(window[(nl + 1)...]))
        }
        if let ws = window.prefix(searchSpan).firstIndex(where: { CharacterSet.whitespaces.contains($0) }), ws + 1 < window.count {
            return String(String.UnicodeScalarView(window[(ws + 1)...]))
        }
        return String(String.UnicodeScalarView(window))
    }

    /// Keep the start of `text` (adjacent to the selection) exactly; cut the far
    /// end at a paragraph, then word, boundary.
    static func trimFarEnd(_ text: String, limit: Int) -> String {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count > limit else { return text }
        let window = Array(scalars.prefix(limit))
        let searchStart = window.count - min(window.count, limit / 2)
        let tail = window[searchStart...]
        if let nl = tail.lastIndex(where: { $0 == "\n" }), nl > 0 {
            return String(String.UnicodeScalarView(window[..<nl]))
        }
        if let ws = tail.lastIndex(where: { CharacterSet.whitespaces.contains($0) }), ws > 0 {
            return String(String.UnicodeScalarView(window[..<ws]))
        }
        return String(String.UnicodeScalarView(window))
    }

    /// Tentative prose/code classification. It only informs the model; code is
    /// protected by the prompt either way.
    public static func classify(_ text: String) -> SelectionKind {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return .unknown }
        var codeLines = 0
        var proseLines = 0
        for line in lines {
            if looksLikeCode(line) { codeLines += 1 } else if looksLikeProse(line) { proseLines += 1 }
        }
        if codeLines == 0 && proseLines == 0 { return .unknown }
        if codeLines == 0 { return .prose }
        if proseLines == 0 { return .code }
        return .mixed
    }

    static func looksLikeCode(_ line: String) -> Bool {
        let codeMarkers = ["{", "}", "();", "=>", "->", "==", "!=", "&&", "||", "::", "</", "/>", "#include", "#!/"]
        let keywords = ["func ", "def ", "class ", "return ", "import ", "const ", "let ", "var ", "public ",
                        "private ", "if (", "for (", "while (", "fn ", "SELECT ", "#define "]
        let hits = codeMarkers.filter { line.contains($0) }.count
        if line.hasSuffix(";") || line.hasSuffix("{") || line.hasSuffix("}") { return true }
        if keywords.contains(where: { line.hasPrefix($0) }) && (line.contains("(") || line.contains("=") || line.contains(":")) { return true }
        return hits >= 2
    }

    static func looksLikeProse(_ line: String) -> Bool {
        let words = line.split(whereSeparator: { $0 == " " })
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return words.count >= 3 && letters * 2 >= line.unicodeScalars.count
    }
}
