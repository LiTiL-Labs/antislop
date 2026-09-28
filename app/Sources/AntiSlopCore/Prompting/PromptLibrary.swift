import Foundation

/// Trusted, developer-versioned editorial instructions compiled into the app.
/// Only allowlisted profile IDs map to rule bodies; there is no path, URL or
/// user-supplied skill lookup.
public struct PromptLibrary: Sendable {
    public let primaryInstructions: String
    let profileRules: [StyleProfileID: String]

    public static let bundled: PromptLibrary = {
        do {
            return try PromptLibrary(
                primaryMarkdown: EmbeddedPrompts.primary,
                noAISlopMarkdown: EmbeddedPrompts.noAISlop,
                humanizerMarkdown: EmbeddedPrompts.humanizer
            )
        } catch {
            fatalError("Embedded prompt resources are malformed: \(error)")
        }
    }()

    public enum ParseError: Error, Equatable {
        case missingSection(String)
        case versionMismatch(String)
    }

    init(primaryMarkdown: String, noAISlopMarkdown: String, humanizerMarkdown: String) throws {
        guard primaryMarkdown.hasPrefix("# Internal primary prompt — version \(ContractVersion.prompt)") else {
            throw ParseError.versionMismatch("primary")
        }
        guard noAISlopMarkdown.hasPrefix("# No AI Slop — reviewed app profile \(ContractVersion.profileRevision)") else {
            throw ParseError.versionMismatch("no-ai-slop")
        }
        guard humanizerMarkdown.hasPrefix("# Humanizer — reviewed app profile \(ContractVersion.profileRevision)") else {
            throw ParseError.versionMismatch("humanizer")
        }
        primaryInstructions = try Self.section(named: "Instruction body", in: primaryMarkdown)
        profileRules = [
            .noAISlop: try Self.section(named: "Editorial rule body", in: noAISlopMarkdown),
            .humanizer: try Self.section(named: "Editorial rule body", in: humanizerMarkdown),
        ]
    }

    /// The reviewed rule body for a profile, or nil for `.none`.
    public func rules(for profile: StyleProfileID) -> String? {
        profileRules[profile]
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
        Anti-slop's two writing styles are reviewed adaptations, not endorsements by their authors.

        No AI Slop by Peter Yang — https://github.com/petergyang/no-ai-slop (revision 000650b1)

        \(EmbeddedPrompts.noAISlopLicense)

        Humanizer by Siqi Chen (blader) — https://github.com/blader/humanizer (revision 225a6f39)

        \(EmbeddedPrompts.humanizerLicense)
        """
    }
}
