#if os(macOS)
import AntiSlopCore
import AppKit
import Carbon

/// Draft state for the one settings screen (first launch and later). Nothing
/// is persisted until Done validates and saves atomically.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var draft: AppSettings
    @Published var readiness: [ProviderID: ReadinessState] = [:]
    @Published var manageExpanded = false
    @Published var recording = false
    @Published var recorderHint: String?
    @Published var shortcutMessage: String?
    @Published var shortcutIsError = false
    @Published var shortcutWarnings: [String] = []
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
    var onAcknowledgements: () -> Void = {}
    var canRegister: (ShortcutBinding) -> OSStatus = { _ in 0 }
    var systemHotKeys: () -> [SystemHotKey] = { [] }

    private var monitor: Any?

    init(settings: AppSettings, isFirstLaunch: Bool, notice: String?) {
        self.draft = settings
        self.isFirstLaunch = isFirstLaunch
        self.notice = notice
        if let g = settings.styleGuide {
            guideLabel = g.label
            guideText = g.text
        }
        if let s = settings.shortcut {
            shortcutWarnings = ShortcutAdvisor.assess(s, systemHotKeys: []).warnings
        }
        moreOptions = settings.writingPreferences.avoidEmDashes
    }

    // MARK: Shortcut recording

    func beginRecording() {
        stopMonitor()
        recording = true
        recorderHint = "Press the key or combination you want to use."
        shortcutMessage = nil
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
        guard recording else { return false }
        if event.type == .flagsChanged {
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            recorderHint = mods.isEmpty ? "Press the key or combination you want to use."
                : "Now press a key to go with the modifier."
            return true
        }
        if event.isARepeat { return true }
        record(keyCode: Int(event.keyCode), flags: event.modifierFlags, characters: event.charactersIgnoringModifiers)
        return true
    }

    func cancelRecording() {
        recording = false
        recorderHint = nil
        stopMonitor()
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Record exactly what was pressed. Never substitutes another key.
    func record(keyCode: Int, flags: NSEvent.ModifierFlags, characters: String?) {
        recording = false
        recorderHint = nil
        stopMonitor()
        var mods: [ShortcutModifier] = []
        if flags.contains(.command) { mods.append(.command) }
        if flags.contains(.option) { mods.append(.option) }
        if flags.contains(.control) { mods.append(.control) }
        if flags.contains(.shift) { mods.append(.shift) }
        // macOS sets the function flag on F-keys and arrows itself; only a held Fn/Globe counts.
        if flags.contains(.function) && !KeyCodes.implicitFunctionFlag.contains(keyCode) { mods.append(.function) }
        let label = KeyCodes.label(keyCode: keyCode, character: characters, modifiers: mods)
        let candidate = ShortcutBinding(keyCode: keyCode, displayLabel: label, modifiers: mods)
        let assessment = ShortcutAdvisor.assess(candidate, systemHotKeys: systemHotKeys())
        if let blocking = assessment.blocking {
            shortcutMessage = blocking
            shortcutIsError = true
            return // the previous assignment stays in the draft
        }
        let status = canRegister(candidate)
        guard status == 0 else {
            shortcutMessage = "\(label): \(HotKeyManager.describe(status))"
            shortcutIsError = true
            return
        }
        draft.shortcut = candidate
        shortcutWarnings = assessment.warnings
        shortcutIsError = false
        shortcutMessage = "\(label) is ready to use after you choose Done."
    }

    func removeShortcut() {
        cancelRecording()
        draft.shortcut = nil
        shortcutWarnings = []
        shortcutIsError = false
        shortcutMessage = "No key assigned. Use the Anti-slop menu bar item to open settings or rewrite a selection."
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
