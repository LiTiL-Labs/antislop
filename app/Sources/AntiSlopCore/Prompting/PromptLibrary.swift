import Foundation

/// Trusted, developer-versioned editorial instructions compiled into the app.
/// One consolidated editorial standard; there is no runtime skill or profile lookup.
public struct PromptLibrary: Sendable {
    public let primaryInstructions: String
    /// Replaces the primary prompt in slop-detection mode.
    public let detectionInstructions: String
    public static let bundled: PromptLibrary = {
        do { return try PromptLibrary(primaryMarkdown: EmbeddedPrompts.primary) }
        catch { fatalError("Embedded prompt resources are malformed: \(error)") }
    }()

    public enum ParseError: Error, Equatable {
        case missingSection(String)
        case versionMismatch(String)
    }

    init(primaryMarkdown: String, detectMarkdown: String = EmbeddedPrompts.detect) throws {
        guard primaryMarkdown.hasPrefix("# Internal primary prompt — version \(ContractVersion.prompt)") else {
            throw ParseError.versionMismatch("primary")
        }
        guard detectMarkdown.hasPrefix("# Internal slop-detection prompt — version \(ContractVersion.prompt)") else {
            throw ParseError.versionMismatch("detect")
        }
        primaryInstructions = try Self.section(named: "Instruction body", in: primaryMarkdown)
        detectionInstructions = try Self.section(named: "Instruction body", in: detectMarkdown)
    }

    /// Text after `## <name>` up to the next level-2 heading or end of file.
    static func section(named name: String, in markdown: String) throws -> String {
        let lines = markdown.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "## \(name)") else { throw ParseError.missingSection(name) }
        var body: [String] = []
        for line in lines[(start + 1)...] {
            if line.hasPrefix("## ") { break }
            body.append(line)
        }
        let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ParseError.missingSection(name) }
        return text
    }
}

/// Attribution for the reviewed profiles' upstream sources (MIT).
public enum Acknowledgements {
    public static var text: String {
        """
        LiTiL Labs' consolidated Anti-Slop prompt includes adaptations of these sources, without endorsement by their authors.

        No AI Slop by Peter Yang — https://github.com/petergyang/no-ai-slop (revision 000650b1)

        \(EmbeddedPrompts.noAISlopLicense)

        Humanizer by Siqi Chen (blader) — https://github.com/blader/humanizer (revision 225a6f39)

        \(EmbeddedPrompts.humanizerLicense)
        """
    }
}
