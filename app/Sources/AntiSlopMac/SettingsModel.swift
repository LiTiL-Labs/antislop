#if os(macOS)
import AntiSlopCore
import AppKit
import Carbon

/// What the settings screen knows about one connection's model list.
enum ModelCatalogState: Equatable {
    case loading
    case loaded([ModelOption])
    case failed(String)
}

/// Draft state for the one settings screen (first launch and later). Nothing
/// is persisted until Done validates and saves atomically.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var draft: AppSettings
    @Published var readiness: [ProviderID: ReadinessState] = [:]
    @Published var catalogs: [ProviderID: ModelCatalogState] = [:]
    @Published var manageExpanded = false
    /// Which key is being recorded, if any.
    @Published var recording: HotKeyAction?
    @Published var recorderHint: String?
    @Published var shortcutMessage: [HotKeyAction: String] = [:]
    @Published var shortcutIsError: [HotKeyAction: Bool] = [:]
    @Published var shortcutWarnings: [HotKeyAction: [String]] = [:]
    @Published var accessibilityTrusted = AX.trusted(prompt: false)
    @Published var guideExpanded = false
    @Published var guideLabel = ""
    @Published var guideText = ""
    @Published var moreOptions = false
    @Published var errors: [String] = []
    @Published var notice: String?
    /// Set once the user picks a connection; automatic preselection stops then.
    var providerChosenByUser = false
    let isFirstLaunch: Bool

    var onDone: (AppSettings) -> String? = { _ in nil }
    var onClose: () -> Void = {}
    var onSignIn: (ProviderID) -> Void = { _ in }
    var onCheck: (ProviderID) -> Void = { _ in }
    /// Ask the connection for its model list (no inference).
    var onLoadModels: (ProviderID) -> Void = { _ in }
    var onAcknowledgements: () -> Void = {}
    var canRegister: (ShortcutBinding, HotKeyAction) -> OSStatus = { _, _ in 0 }
    var systemHotKeys: () -> [SystemHotKey] = { [] }

    private var monitor: Any?
    /// A modifier pressed on its own during recording; recorded if released alone.
    private var loneCandidate: LoneModifierDetector?

    init(settings: AppSettings, isFirstLaunch: Bool, notice: String?) {
        self.draft = settings
        self.isFirstLaunch = isFirstLaunch
        self.notice = notice
        if let g = settings.styleGuide {
            guideLabel = g.label
            guideText = g.text
        }
        for action in HotKeyAction.allCases {
            if let b = Self.binding(settings, action) {
                shortcutWarnings[action] = ShortcutAdvisor.assess(b, systemHotKeys: [], appliesInPanel: action == .rewrite).warnings
            }
        }
        moreOptions = settings.writingPreferences.avoidEmDashes
    }

    // MARK: Shortcut recording

    static func binding(_ s: AppSettings, _ action: HotKeyAction) -> ShortcutBinding? {
        action == .rewrite ? s.shortcut : s.detectShortcut
    }

    func binding(for action: HotKeyAction) -> ShortcutBinding? { Self.binding(draft, action) }

    private func setBinding(_ b: ShortcutBinding?, for action: HotKeyAction) {
        if action == .rewrite { draft.shortcut = b } else { draft.detectShortcut = b }
    }

    static let idleHint = "Press a key, a combination, or a modifier key on its own."

    func beginRecording(_ action: HotKeyAction) {
        stopMonitor()
        recording = action
        recorderHint = Self.idleHint
        shortcutMessage[action] = nil
        loneCandidate = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                return self.handleRecorderEvent(event)
            }
            return consumed ? nil : event
        }
    }

    /// Returns true when the event was used by the recorder (and must not reach other controls).
    private func handleRecorderEvent(_ event: NSEvent) -> Bool {
        guard let action = recording else { return false }
        if event.type == .flagsChanged {
            let code = Int(event.keyCode)
            guard KeyCodes.modifierOnly.contains(code) else { return true }
            let raw = event.modifierFlags.rawValue
            if loneCandidate?.keyCode != code, KeyCodes.modifierState(keyCode: code, flags: raw).isDown || code == KeyCodes.capsLock {
                loneCandidate = LoneModifierDetector(keyCode: code, maxHold: 3)
            }
            if loneCandidate?.flagsChanged(keyCode: code, flags: raw) == true {
                loneCandidate = nil
                record(keyCode: code, flags: [], characters: nil, for: action)
                return true
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            recorderHint = mods.isEmpty ? Self.idleHint
                : "Release it to use \(KeyCodes.modifierKeyNames[code] ?? "that key") on its own, or press another key with it."
            return true
        }
        loneCandidate?.otherKeyDown()
        if event.isARepeat { return true }
        record(keyCode: Int(event.keyCode), flags: event.modifierFlags, characters: event.charactersIgnoringModifiers, for: action)
        return true
    }

    func cancelRecording() {
        recording = nil
        recorderHint = nil
        loneCandidate = nil
        stopMonitor()
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Record exactly what was pressed. Never substitutes another key.
    func record(keyCode: Int, flags: NSEvent.ModifierFlags, characters: String?, for action: HotKeyAction) {
        cancelRecording()
        var mods: [ShortcutModifier] = []
        if flags.contains(.command) { mods.append(.command) }
        if flags.contains(.option) { mods.append(.option) }
        if flags.contains(.control) { mods.append(.control) }
        if flags.contains(.shift) { mods.append(.shift) }
        // macOS sets the function flag on F-keys and arrows itself; only a held Fn/Globe counts.
        if flags.contains(.function) && !KeyCodes.implicitFunctionFlag.contains(keyCode) { mods.append(.function) }
        let label = KeyCodes.label(keyCode: keyCode, character: characters, modifiers: mods)
        let candidate = ShortcutBinding(keyCode: keyCode, displayLabel: label, modifiers: mods)
        let other: HotKeyAction = action == .rewrite ? .detect : .rewrite
        if let taken = binding(for: other), taken.sameKey(as: candidate) {
            shortcutMessage[action] = "\(label) is already your \(other.name). Choose a different key."
            shortcutIsError[action] = true
            return
        }
        let assessment = ShortcutAdvisor.assess(candidate, systemHotKeys: systemHotKeys(), appliesInPanel: action == .rewrite)
        if let blocking = assessment.blocking {
            shortcutMessage[action] = blocking
            shortcutIsError[action] = true
            return // the previous assignment stays in the draft
        }
        let status = canRegister(candidate, action)
        guard status == 0 else {
            shortcutMessage[action] = "\(label): \(HotKeyManager.describe(status))"
            shortcutIsError[action] = true
            return
        }
        setBinding(candidate, for: action)
        shortcutWarnings[action] = assessment.warnings
        shortcutIsError[action] = false
        shortcutMessage[action] = "\(label) is ready to use after you choose Done."
    }

    func removeShortcut(_ action: HotKeyAction) {
        cancelRecording()
        setBinding(nil, for: action)
        shortcutWarnings[action] = []
        shortcutIsError[action] = false
        shortcutMessage[action] = action == .rewrite
            ? "No key assigned. Use the Anti-slop menu bar item to open settings or rewrite a selection."
            : "No key assigned. Use the Anti-slop menu bar item to check a selection for slop."
    }

    // MARK: Model and reasoning

    func loadModelsIfNeeded(_ p: ProviderID) {
        switch catalogs[p] {
        case .loaded?, .loading?: return
        default: onLoadModels(p)
        }
    }

    var preference: ModelPreference { draft.modelPreference(for: draft.providerID) }

    /// The catalog entries offered as choices; Claude Code's own "default" entry is
    /// the Default row instead. A saved model the runtime no longer lists stays visible.
    func modelChoices(_ models: [ModelOption]) -> [ModelOption] {
        var out = models.filter { !$0.isRuntimeDefault }
        if let saved = preference.model, !out.contains(where: { $0.id == saved }) {
            out.append(ModelOption(id: saved, displayName: "\(saved) (not currently offered)"))
        }
        return out
    }

    /// Levels offered for the selected model. With the runtime default, Claude Code's
    /// default entry says what it accepts; otherwise only levels every model accepts.
    func reasoningLevels(_ models: [ModelOption]) -> [String] {
        if let id = preference.model {
            return models.first { $0.id == id }?.reasoningLevels ?? []
        }
        if let def = models.first(where: \.isRuntimeDefault) { return def.reasoningLevels }
        guard let first = models.first else { return [] }
        return first.reasoningLevels.filter { level in models.allSatisfy { $0.reasoningLevels.contains(level) } }
    }

    func selectModel(_ id: String?, catalog: [ModelOption]) {
        var pref = preference
        pref.model = id
        // Keep the reasoning level only if the new model accepts it.
        if let r = pref.reasoning, !reasoningLevels(catalog, model: id).contains(r) { pref.reasoning = nil }
        draft.modelPreferences[draft.providerID] = pref
    }

    func selectReasoning(_ level: String?) {
        var pref = preference
        pref.reasoning = level
        draft.modelPreferences[draft.providerID] = pref
    }

    private func reasoningLevels(_ models: [ModelOption], model: String?) -> [String] {
        let saved = draft.modelPreferences[draft.providerID]
        draft.modelPreferences[draft.providerID] = ModelPreference(model: model)
        defer { draft.modelPreferences[draft.providerID] = saved }
        return reasoningLevels(models)
    }

    // MARK: Guide

    func addOrEditGuide() {
        guideExpanded = true
    }

    func removeGuide() {
        guideLabel = ""
        guideText = ""
        guideExpanded = false
        draft.styleGuide = nil
    }

    // MARK: Done

    func done() {
        cancelRecording()
        var candidate = draft
        let label = guideLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if guideExpanded || draft.styleGuide != nil {
            candidate.styleGuide = (label.isEmpty && guideText.isBlank) ? nil : StyleGuide(label: label, text: guideText)
        }
        let issues = SettingsValidator.issues(in: candidate)
        guard issues.isEmpty else {
            errors = issues.map(\.message)
            return
        }
        if let failure = onDone(candidate) {
            errors = [failure]
            return
        }
        errors = []
        draft = candidate
        onClose()
    }

    func refreshAccessibility() {
        accessibilityTrusted = AX.trusted(prompt: false)
    }

    func requestAccessibility() {
        _ = AX.trusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func state(for p: ProviderID) -> ReadinessState {
        readiness[p] ?? .checking
    }
}
#endif
