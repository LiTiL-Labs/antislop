#if os(macOS)
import AntiSlopCore
import AppKit
import Carbon
import os
import SwiftUI

public enum AntiSlopApplication {
    /// Entry point. Call on the main thread (main.swift wraps it in MainActor.assumeIsolated).
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(controller) { app.run() }
    }
}

/// Owns the resident menu-bar entry, settings, trigger, panel and the single
/// active rewrite session.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    let log = Logger(subsystem: "local.antislop", category: "app")
    let store: SettingsStore
    var settings: AppSettings
    var firstLaunch = false
    var settingsNotice: String?
    let hotKeys = HotKeyManager()
    let panel = PanelController()
    let toast = Toast()
    let fixtureMode: Bool
    var providers: [ProviderID: RewriteProvider] = [:]
    var readiness: [ProviderID: ReadinessState] = [:]
    var capturer: AccessibilityCapture!
    var coordinator: SessionCoordinator!
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    var settingsModel: SettingsModel?
    var acknowledgementsWindow: NSWindow?
    var lastExternalApp: NSRunningApplication?
    var sourceApp: NSRunningApplication?
    var accessTimer: Timer?

    override init() {
        let env = ProcessInfo.processInfo.environment
        let args = CommandLine.arguments
        let localStore: SettingsStore
        if let custom = env["ANTISLOP_SETTINGS_PATH"], !custom.isEmpty {
            localStore = SettingsStore(fileURL: URL(fileURLWithPath: custom))
        } else {
            localStore = SettingsStore(fileURL: SettingsStore.defaultLocation())
        }
        var loaded = AppSettings.firstLaunch(provider: .claudeCode)
        var isFirst = false
        var notice: String? = nil
        switch localStore.load() {
        case .firstLaunch:
            isFirst = true
        case .loaded(let s):
            loaded = s
        case .unreadable(let path):
            isFirst = true
            notice = "Your previous settings couldn't be read and were kept at \(path). Set up again below."
        }
        fixtureMode = args.contains("--fixture-provider") || env["ANTISLOP_FIXTURE_PROVIDER"] == "1"
        store = localStore
        settings = loaded
        firstLaunch = isFirst
        settingsNotice = notice
        super.init()
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusItem()
        if fixtureMode {
            let fixture = FixtureProvider(delay: 0.9)
            providers = [.codex: fixture, .claudeCode: fixture]
        } else {
            providers = [.codex: CodexProvider(), .claudeCode: ClaudeCodeProvider()]
        }
        capturer = AccessibilityCapture(lastExternalApp: { [weak self] in self?.lastExternalApp })
        coordinator = SessionCoordinator(
            capturer: capturer,
            replacer: AccessibilityReplacer(),
            settings: { [weak self] in self?.settings ?? AppSettings(providerID: .claudeCode) },
            provider: { [weak self] id in self?.providers[id] ?? FixtureProvider() }
        )
        coordinator.onChange = { [weak self] in self?.sessionChanged() }
        coordinator.diagnostics = { [weak self] line in self?.log.info("\(line, privacy: .public)") }
        wirePanel()

        hotKeys.onPress = { [weak self] in self?.handleTrigger(fromKey: true) }
        if let s = settings.shortcut {
            let status = hotKeys.apply(s)
            if status != 0 {
                settingsNotice = "\(s.displayLabel) couldn't be registered: \(HotKeyManager.describe(status)) Choose another key."
                log.error("shortcut registration failed \(status, privacy: .public)")
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(selfBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(selfResignedActive),
                                               name: NSApplication.didResignActiveNotification, object: nil)
        lastExternalApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == getpid() ? nil : $0 }

        refreshAllReadiness()
        if firstLaunch || settings.shortcut == nil || settingsNotice != nil || !AX.trusted(prompt: false) {
            openSettings()
        }
    }

    /// Launching the app again (e.g. from Finder) always offers settings, even
    /// if the shortcut is missing or broken.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    @objc func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != getpid() else { return }
        lastExternalApp = app
    }

    /// While Anti-slop is active its own fields receive the assigned key.
    @objc func selfBecameActive() {
        hotKeys.suspend()
        log.notice("active; trigger suspended")
    }
    @objc func selfResignedActive() {
        let status = hotKeys.resume()
        log.notice("inactive; trigger resumed, status \(status, privacy: .public)")
    }

    // MARK: Menus

    func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Anti-slop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        // Edit menu so standard editing shortcuts work in the panel and settings.
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "Anti-slop")
            button.image?.isTemplate = true
            button.toolTip = "Anti-slop"
        }
        let menu = NSMenu()
        let rewrite = NSMenuItem(title: "Rewrite Selection", action: #selector(rewriteFromMenu), keyEquivalent: "")
        rewrite.target = self
        menu.addItem(rewrite)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let ack = NSMenuItem(title: "Acknowledgements", action: #selector(showAcknowledgements), keyEquivalent: "")
        ack.target = self
        menu.addItem(ack)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Anti-slop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc func openSettingsAction() { openSettings() }
    @objc func rewriteFromMenu() { handleTrigger() }

    // MARK: Trigger → capture → panel

    /// `fromKey` is true when the assigned key (which may still be held) started it.
    func handleTrigger(fromKey: Bool = false) {
        let held = fromKey ? hotKeys.binding.map { UInt16($0.keyCode) } : nil
        if !AX.trusted(prompt: false) {
            toast.show(CaptureRefusal.accessibilityNotTrusted.message)
            openSettings()
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        sourceApp = (front?.processIdentifier == getpid()) ? lastExternalApp : front
        let result = coordinator.trigger()
        log.notice("trigger \(String(describing: result), privacy: .public)")
        switch result {
        case .started:
            panel.model.reset()
            panel.model.update(from: coordinator.session)
            panel.show(anchor: coordinator.snapshot?.selectionBounds, heldKeyCode: held)
            DevSnapshot.write(panel.window, name: "app-panel-generating.png", after: 0.3)
        case .focusExisting:
            panel.focus(heldKeyCode: held)
        case .refused(let r):
            toast.show(r.message)
            if r == .accessibilityNotTrusted { openSettings() }
        }
    }

    func wirePanel() {
        let m = panel.model
        m.onApply = { [weak self] in self?.apply() }
        m.onClose = { [weak self] in self?.closePanel(returnFocus: true) }
        m.onSettings = { [weak self] in self?.openSettings() }
        m.onEdit = { [weak self] text in self?.coordinator.edit(text) }
        m.onAction = { [weak self] action in self?.perform(action) }
    }

    func sessionChanged() {
        guard let s = coordinator.session else { return }
        panel.model.update(from: s)
        switch s.phase {
        case .ready: DevSnapshot.write(panel.window, name: "app-panel-ready.png")
        case .targetChanged, .failed: DevSnapshot.write(panel.window, name: "app-panel-error.png")
        default: break
        }
        if s.phase == .succeeded {
            closePanel(returnFocus: true)
        }
    }

    func apply() {
        guard let s = coordinator.session, s.applyAvailability == .enabled else { return }
        Task { @MainActor in
            await self.coordinator.apply()
        }
    }

    func perform(_ action: PanelAction) {
        switch action {
        case .retry:
            coordinator.retry()
        case .openSettings:
            openSettings()
        case .copyDraft:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(coordinator.session?.draft ?? "", forType: .string)
            toast.show("Draft copied.")
        case .useCurrentSelection:
            if let refusal = coordinator.retarget() {
                toast.show(refusal.message)
            } else {
                sourceApp = coordinator.snapshot.flatMap { NSRunningApplication(processIdentifier: $0.target.processID) }
            }
        }
    }

    /// Dismiss after confirmed replacement or explicit close. Close cancels pending work.
    func closePanel(returnFocus: Bool) {
        if coordinator.session?.phase == .applying { return }
        coordinator.cancel()
        let app = sourceApp
        let closing = coordinator.session
        panel.hide { [weak self] in
            guard let self else { return }
            // A new trigger during the fade owns the coordinator now; leave it alone.
            if self.coordinator.session === closing { self.coordinator.clear() }
            guard returnFocus else { return }
            let requested = app?.activate(options: []) ?? false
            self.log.notice("panel closed; focus return requested: \(requested, privacy: .public)")
            // Never stay the active app with nothing on screen: the assigned key is
            // suspended while Anti-slop is active, so it would silently stop working.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                MainActor.assumeIsolated { self?.stepBackIfIdle() }
            }
        }
    }

    /// Hide (which reactivates the previous app) when active with no panel or settings on screen.
    func stepBackIfIdle() {
        guard NSApp.isActive, !panel.isVisible, !(settingsWindow?.isVisible ?? false) else { return }
        log.notice("still active with no window after closing the panel; hiding")
        NSApp.hide(nil)
    }

    // MARK: Settings

    func openSettings() {
        if let w = settingsWindow, w.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let model = SettingsModel(settings: settings, isFirstLaunch: firstLaunch,
                                  notice: settingsNotice ?? (firstLaunch ? "Welcome. Choose an AI connection and a key, then select text in any app and press it." : nil))
        model.readiness = readiness
        model.canRegister = { [weak self] b in self?.hotKeys.canRegister(b) ?? OSStatus(-1) }
        model.systemHotKeys = { SystemShortcuts.enabled() }
        model.onDone = { [weak self] new in self?.commit(new) }
        model.onClose = { [weak self] in self?.settingsWindow?.close() }
        model.onSignIn = { [weak self] p in self?.signIn(p) }
        model.onCheck = { [weak self] p in self?.checkReadiness(p) }
        model.onAcknowledgements = { [weak self] in self?.showAcknowledgements() }
        settingsModel = model

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 820),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Anti-slop"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .white
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        if let screen = NSScreen.main {
            let h = min(820, screen.visibleFrame.height - 40)
            window.setContentSize(NSSize(width: 540, height: h))
        }
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DevSnapshot.write(window, name: "app-settings.png", after: 1.2)

        accessTimer?.invalidate()
        accessTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            onMainAsync {
                guard let self, let w = self.settingsWindow, w.isVisible else { return }
                self.settingsModel?.refreshAccessibility()
            }
        }
        for p in ProviderID.allCases where readiness[p] == nil {
            checkReadiness(p)
        }
        preselectProviderIfFirstLaunch()
    }

    /// Done: validate registration, save atomically, then adopt. A failed key
    /// registration leaves the previous valid key in place and nothing saved.
    func commit(_ new: AppSettings) -> String? {
        if new.shortcut != settings.shortcut {
            let status = hotKeys.apply(new.shortcut)
            if status != 0 {
                return "\(new.shortcut?.displayLabel ?? "That key") couldn't be registered: \(HotKeyManager.describe(status))"
            }
        }
        do {
            try store.save(new)
        } catch {
            _ = hotKeys.apply(settings.shortcut)
            return "Couldn't save settings. Nothing was changed."
        }
        settings = new
        firstLaunch = false
        settingsNotice = nil
        return nil
    }

    func refreshAllReadiness() {
        for p in ProviderID.allCases { checkReadiness(p) }
    }

    func checkReadiness(_ p: ProviderID) {
        guard let provider = providers[p] else { return }
        readiness[p] = .checking
        settingsModel?.readiness[p] = .checking
        Task { @MainActor in
            let state = await provider.checkReadiness()
            self.readiness[p] = state
            self.settingsModel?.readiness[p] = state
            self.preselectProviderIfFirstLaunch()
            self.log.info("readiness \(p.rawValue, privacy: .public): \(state.label, privacy: .public)")
        }
    }

    /// First launch: preselect the only ready runtime; with both or neither
    /// ready, the visible choice stays as shown. Never overrides the user's pick.
    func preselectProviderIfFirstLaunch() {
        guard firstLaunch, let model = settingsModel, !model.providerChosenByUser,
              ProviderID.allCases.allSatisfy({ readiness[$0] != nil && readiness[$0] != .checking }) else { return }
        let ready = Set(ProviderID.allCases.filter { readiness[$0]?.isReady == true })
        model.draft.providerID = AppSettings.firstLaunchProvider(ready: ready)
    }

    func signIn(_ p: ProviderID) {
        guard let provider = providers[p] else { return }
        Task { @MainActor in
            guard let cmd = await provider.signInCommand() else {
                self.settingsModel?.readiness[p] = .unavailable("Install \(p.displayName) first, then check again.")
                return
            }
            do {
                try SignInLauncher.open(cmd)
            } catch {
                self.toast.show("Couldn't open \(p.displayName) sign-in.")
            }
        }
    }

    // MARK: Acknowledgements

    @objc func showAcknowledgements() {
        if let w = acknowledgementsWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Acknowledgements"
        window.isReleasedWhenClosed = false
        let scroll = NSTextView.scrollableTextView()
        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.string = Acknowledgements.text
            tv.font = NSFont.systemFont(ofSize: 12)
            tv.textContainerInset = NSSize(width: 14, height: 14)
        }
        window.contentView = scroll
        window.center()
        acknowledgementsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
#endif
