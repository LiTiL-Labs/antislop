import Foundation

public enum ShortcutModifier: String, Codable, CaseIterable, Sendable {
    case command, option, control, shift, function

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        case .function: return "fn "
        }
    }

    /// macOS display order: ⌃⌥⇧⌘.
    static let displayOrder: [ShortcutModifier] = [.function, .control, .option, .shift, .command]
}

/// Normalized record of the user's chosen trigger. A valid record does not
/// establish that registration works; see `ShortcutAdvisor` and the platform
/// registrar for runtime validation.
public struct ShortcutBinding: Codable, Equatable, Hashable, Sendable {
    public var keyCode: Int
    public var displayLabel: String
    public var modifiers: [ShortcutModifier]
    public var enabled: Bool

    public init(keyCode: Int, displayLabel: String, modifiers: [ShortcutModifier], enabled: Bool = true) {
        self.keyCode = keyCode
        self.displayLabel = displayLabel
        self.modifiers = ShortcutModifier.displayOrder.filter { modifiers.contains($0) }
        self.enabled = enabled
    }

    public var modifierSet: Set<ShortcutModifier> { Set(modifiers) }

    /// A modifier key pressed and released on its own (e.g. Right ⌥, Fn, Caps Lock).
    public var isLoneModifier: Bool { KeyCodes.modifierOnly.contains(keyCode) && modifiers.isEmpty }

    /// Same physical trigger, regardless of label or enabled state.
    public func sameKey(as other: ShortcutBinding) -> Bool {
        keyCode == other.keyCode && modifierSet == other.modifierSet
    }

    enum CodingKeys: String, CodingKey {
        case keyCode = "key_code"
        case displayLabel = "display_label"
        case modifiers, enabled
    }
}

/// Local preferences (schemas/settings.schema.json). No secrets and no readiness claims.
public struct AppSettings: Equatable, Sendable {
    public var schemaVersion: String = ContractVersion.schema
    public var providerID: ProviderID
    public var shortcut: ShortcutBinding?
    /// Second, independent key for slop-detection mode.
    public var detectShortcut: ShortcutBinding?
    public var styleProfileID: StyleProfileID
    public var writingPreferences: WritingPreferences
    public var customWriterInstructions: String
    public var styleGuide: StyleGuide?
    /// Model and reasoning choice per connection; absent means the runtime default.
    public var modelPreferences: [ProviderID: ModelPreference] = [:]

    public func modelPreference(for p: ProviderID) -> ModelPreference {
        modelPreferences[p] ?? .runtimeDefault
    }

    public init(
        providerID: ProviderID,
        shortcut: ShortcutBinding? = nil,
        detectShortcut: ShortcutBinding? = nil,
        styleProfileID: StyleProfileID = .noAISlop,
        writingPreferences: WritingPreferences = .defaults,
        customWriterInstructions: String = "",
        styleGuide: StyleGuide? = nil
    ) {
        self.providerID = providerID
        self.shortcut = shortcut
        self.detectShortcut = detectShortcut
        self.styleProfileID = styleProfileID
        self.writingPreferences = writingPreferences
        self.customWriterInstructions = customWriterInstructions
        self.styleGuide = styleGuide
    }

    /// First-launch draft. The provider shown is a visible, changeable choice on
    /// the settings screen; the app preselects a ready runtime when exactly one is
    /// ready (see `AppSettings.firstLaunchProvider`).
    public static func firstLaunch(provider: ProviderID) -> AppSettings {
        AppSettings(providerID: provider)
    }

    /// Choose the initial provider: the only ready runtime if exactly one is
    /// ready; otherwise Claude Code, with the choice presented on screen.
    public static func firstLaunchProvider(ready: Set<ProviderID>) -> ProviderID {
        if ready.count == 1, let only = ready.first { return only }
        return .claudeCode
    }
}

extension AppSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case providerID = "provider_id"
        case shortcut
        case detectShortcut = "detect_shortcut"
        case styleProfileID = "style_profile_id"
        case writingPreferences = "writing_preferences"
        case customWriterInstructions = "custom_writer_instructions"
        case styleGuide = "style_guide"
        case modelPreferences = "model_preferences"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        providerID = try c.decode(ProviderID.self, forKey: .providerID)
        shortcut = try c.decodeIfPresent(ShortcutBinding.self, forKey: .shortcut)
        // Absent in settings saved before slop-detection mode existed.
        detectShortcut = try c.decodeIfPresent(ShortcutBinding.self, forKey: .detectShortcut)
        styleProfileID = try c.decode(StyleProfileID.self, forKey: .styleProfileID)
        writingPreferences = try c.decode(WritingPreferences.self, forKey: .writingPreferences)
        customWriterInstructions = try c.decode(String.self, forKey: .customWriterInstructions)
        styleGuide = try c.decodeIfPresent(StyleGuide.self, forKey: .styleGuide)
        // Absent in settings saved before model selection existed. Unknown provider keys are ignored.
        let raw = try c.decodeIfPresent([String: ModelPreference].self, forKey: .modelPreferences) ?? [:]
        modelPreferences = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in ProviderID(rawValue: k).map { ($0, v) } })
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(providerID, forKey: .providerID)
        try c.encodeNullable(shortcut, forKey: .shortcut)
        try c.encodeNullable(detectShortcut, forKey: .detectShortcut)
        try c.encode(styleProfileID, forKey: .styleProfileID)
        try c.encode(writingPreferences, forKey: .writingPreferences)
        try c.encode(customWriterInstructions, forKey: .customWriterInstructions)
        try c.encodeNullable(styleGuide, forKey: .styleGuide)
        let raw = Dictionary(uniqueKeysWithValues: modelPreferences.filter { $0.value != .runtimeDefault }.map { ($0.key.rawValue, $0.value) })
        try c.encode(raw, forKey: .modelPreferences)
    }
}

public enum SettingsIssue: Equatable, Sendable {
    case customInstructionsTooLong(count: Int)
    case guideLabelMissing
    case guideLabelTooLong(count: Int)
    case guideTextMissing
    case guideTextTooLong(count: Int)
    case shortcutLabelInvalid
    case shortcutsCollide
    case modelChoiceInvalid

    public var message: String {
        switch self {
        case .customInstructionsTooLong(let n):
            return "Custom writing instructions are \(n) characters; the limit is \(Limits.customInstructions)."
        case .guideLabelMissing: return "Give the writing guide a short name."
        case .guideLabelTooLong(let n): return "Guide name is \(n) characters; the limit is \(Limits.guideLabel)."
        case .guideTextMissing: return "Paste the guide excerpt, or remove the guide."
        case .guideTextTooLong(let n): return "Guide excerpt is \(n) characters; the limit is \(Limits.guideText)."
        case .shortcutLabelInvalid: return "The recorded key has no usable label. Record it again."
        case .shortcutsCollide: return "The anti-slop key and the slop-detection key must be different."
        case .modelChoiceInvalid: return "The saved model or reasoning level isn't a valid name. Choose it again."
        }
    }
}

public enum SettingsValidator {
    /// Validation applied on Done. Nothing is truncated to make settings pass.
    public static func issues(in s: AppSettings) -> [SettingsIssue] {
        var out: [SettingsIssue] = []
        let n = s.customWriterInstructions.codePointCount
        if n > Limits.customInstructions { out.append(.customInstructionsTooLong(count: n)) }
        if let g = s.styleGuide {
            let label = g.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty { out.append(.guideLabelMissing) }
            if g.label.codePointCount > Limits.guideLabel { out.append(.guideLabelTooLong(count: g.label.codePointCount)) }
            if g.text.isBlank { out.append(.guideTextMissing) }
            if g.text.codePointCount > Limits.guideText { out.append(.guideTextTooLong(count: g.text.codePointCount)) }
        }
        for k in [s.shortcut, s.detectShortcut].compactMap({ $0 }) {
            if k.displayLabel.isEmpty || k.displayLabel.codePointCount > 80 { out.append(.shortcutLabelInvalid); break }
        }
        if let a = s.shortcut, let b = s.detectShortcut, a.sameKey(as: b) { out.append(.shortcutsCollide) }
        if s.modelPreferences.values.contains(where: { !$0.isValid }) { out.append(.modelChoiceInvalid) }
        return out
    }
}

public enum SettingsLoadResult: Equatable, Sendable {
    /// No settings file yet: show the settings screen as onboarding.
    case firstLaunch
    case loaded(AppSettings)
    /// The file could not be read as current settings. It was moved aside, not
    /// deleted, so writer instructions and keys can be recovered by hand.
    case unreadable(preservedAt: String)
}

/// Atomic JSON persistence for `AppSettings`. Drafts and session content are
/// never written here.
public final class SettingsStore: @unchecked Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// ~/Library/Application Support/Anti-slop/settings.json on macOS.
    public static func defaultLocation() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Anti-slop", isDirectory: true).appendingPathComponent("settings.json")
    }

    public func load() -> SettingsLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .firstLaunch }
        do {
            let data = try Data(contentsOf: fileURL)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            guard settings.schemaVersion == ContractVersion.schema else {
                return .unreadable(preservedAt: try preserveUnreadable())
            }
            return .loaded(settings)
        } catch {
            let preserved = (try? preserveUnreadable()) ?? fileURL.path
            return .unreadable(preservedAt: preserved)
        }
    }

    public func save(_ settings: AppSettings) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let data = try e.encode(settings)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func preserveUnreadable() throws -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = fileURL.deletingLastPathComponent().appendingPathComponent("settings.unreadable-\(stamp).json")
        try FileManager.default.moveItem(at: fileURL, to: dest)
        return dest.path
    }
}
