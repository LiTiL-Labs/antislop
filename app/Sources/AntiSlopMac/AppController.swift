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
    /// Developer prompt/response window (`--debug-prompts`); nil in normal use.
    let debugInspector: DebugInspector? = DebugInspector.isEnabled ? DebugInspector() : nil
    let fixtureMode: Bool
    var providers: [ProviderID: RewriteProvider] = [:]
    var readiness: [ProviderID: ReadinessState] = [:]
    var capturer: AccessibilityCapture!
    var coordinator: SessionCoordinator!
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    var settingsModel: SettingsModel?
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
        if let inspector = debugInspector {
            coordinator.onTrace = { [weak self] trace in
                inspector.show(trace)
                inspector.place(beside: self?.panel.window)
            }
        }
        wirePanel()

        hotKeys.onPress = { [weak self] action in
            self?.handleTrigger(mode: action == .detect ? .detect : .rewrite, fromKey: true)
        }
        for action in HotKeyAction.allCases {
            guard let s = SettingsModel.binding(settings, action) else { continue }
            let status = hotKeys.apply(s, for: action)
            if status != 0 {
                settingsNotice = "\(s.displayLabel) couldn't be registered as your \(action.name): \(HotKeyManager.describe(status)) Choose another key."
                log.error("shortcut registration failed \(status, privacy: .public)")
            }
        }
        panel.triggerKey = hotKeys.binding(for: .rewrite)

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
            button.image = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "Anti-Slop")
            if button.image == nil { button.title = "AS" }
            button.setAccessibilityLabel("Anti-Slop menu")
            button.image?.isTemplate = true
            button.toolTip = "Anti-Slop • LiTiL Labs"
        }
        let menu = NSMenu()
        let rewrite = NSMenuItem(title: "Rewrite Selection", action: #selector(rewriteFromMenu), keyEquivalent: "")
        rewrite.target = self
        menu.addItem(rewrite)
        let check = NSMenuItem(title: "Check Selection for Slop", action: #selector(detectFromMenu), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        let settingsItem = NSMenuItem(title: "Open Anti-Slop Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let ack = NSMenuItem(title: "LiTiL Labs - Law bro edition", action: #selector(openLiTiL), keyEquivalent: "")
        ack.target = self
        menu.addItem(ack)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Anti-slop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc func openLiTiL() { NSWorkspace.shared.open(URL(string: "https://litil.ai")!) }

    @objc func openSettingsAction() { openSettings() }
    @objc func rewriteFromMenu() { handleTrigger(mode: .rewrite) }
    @objc func detectFromMenu() { handleTrigger(mode: .detect) }

    // MARK: Trigger → capture → panel

    /// `fromKey` is true when an assigned key (which may still be held) started it.
    func handleTrigger(mode: SessionMode, fromKey: Bool = false) {
        let action: HotKeyAction = mode == .detect ? .detect : .rewrite
        // A lone modifier fires on release, so nothing is still held.
        let held = fromKey ? hotKeys.binding(for: action).flatMap { $0.isLoneModifier ? nil : UInt16($0.keyCode) } : nil
        if !AX.trusted(prompt: false) {
            toast.show(CaptureRefusal.accessibilityNotTrusted.message)
            openSettings()
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        sourceApp = (front?.processIdentifier == getpid()) ? lastExternalApp : front
        // The anti-slop key over an open slop check rewrites that same selection.
        if mode == .rewrite, coordinator.isActive, coordinator.session?.mode == .detect, coordinator.switchToRewrite() {
            log.notice("trigger: detection switched to rewrite")
            panel.focus(heldKeyCode: held)
            return
        }
        let result = coordinator.trigger(mode: mode)
        log.notice("trigger \(mode.rawValue, privacy: .public) \(String(describing: result), privacy: .public)")
        switch result {
        case .started:
            panel.model.reset()
            panel.model.update(from: coordinator.session)
            panel.show(anchor: coordinator.snapshot?.selectionBounds, heldKeyCode: held)
            // The panel animates in; place the inspector against its final frame.
            if let inspector = debugInspector {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    MainActor.assumeIsolated { inspector.place(beside: self?.panel.window) }
                }
            }
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
        m.onTriggerKey = { [weak self] in self?.triggerKeyInPanel() }
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

    /// The anti-slop key inside the panel: apply a ready rewrite, or rewrite the
    /// selection a slop check was looking at. Otherwise it does nothing.
    func triggerKeyInPanel() {
        guard let s = coordinator.session else { return }
        if s.mode == .detect {
            if coordinator.switchToRewrite() { panel.model.reset() ; panel.model.update(from: coordinator.session) }
        } else {
            apply()
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
        // Only work still in flight needs cancelling; a finished session is left as is.
        if coordinator.isActive { coordinator.cancel() }
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
        log.notice("still active with no window open; hiding")
        NSApp.hide(nil)
    }

    // MARK: Settings

    func openSettings() {
        if let w = settingsWindow, w.isVisible {
            activateAntiSlop()
            w.makeKeyAndOrderFront(nil)
            return
        }
        let model = SettingsModel(settings: settings, isFirstLaunch: firstLaunch,
                                  notice: settingsNotice ?? (firstLaunch ? "Welcome. Choose an AI connection and a key, then select text in any app and press it." : nil))
        model.readiness = readiness
        model.canRegister = { [weak self] b, action in self?.hotKeys.canRegister(b, for: action) ?? OSStatus(-1) }
        model.systemHotKeys = { SystemShortcuts.enabled() }
        model.onDone = { [weak self] new in self?.commit(new) }
        model.onClose = { [weak self] in self?.settingsWindow?.close() }
        model.onSignIn = { [weak self] p in self?.signIn(p) }
        model.onCheck = { [weak self] p in self?.checkReadiness(p) }
        model.onLoadModels = { [weak self] p in self?.loadModels(p) }
        settingsModel = model

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 820),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Anti-Slop"
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
        activateAntiSlop()
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
        var changed: [HotKeyAction] = []
        func rollBack() {
            for a in changed { _ = hotKeys.apply(SettingsModel.binding(settings, a), for: a) }
        }
        for action in HotKeyAction.allCases {
            let b = SettingsModel.binding(new, action)
            guard b != SettingsModel.binding(settings, action) else { continue }
            let status = hotKeys.apply(b, for: action)
            if status != 0 {
                rollBack()
                return "\(b?.displayLabel ?? "That key") couldn't be registered as your \(action.name): \(HotKeyManager.describe(status))"
            }
            changed.append(action)
        }
        do {
            try store.save(new)
        } catch {
            rollBack()
            return "Couldn't save settings. Nothing was changed."
        }
        settings = new
        panel.triggerKey = new.shortcut
        firstLaunch = false
        settingsNotice = nil
        if !fixtureMode {
            do { try LoginItem.apply(new.launchAtLogin) }
            catch {
                return "Your writing settings were saved, but macOS couldn't change startup: \(error.localizedDescription) Use Open Login Items to check access, then try Done again."
            }
            if new.launchAtLogin && LoginItem.requiresApproval {
                return "Settings saved. Allow Anti-Slop in macOS Login Items to finish enabling startup."
            }
        }
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
            // A fresh sign-in can change which models the account offers.
            if state.isReady, case .failed? = self.settingsModel?.catalogs[p] { self.loadModels(p) }
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

    /// Ask a connection for its model list and hand it to the open settings screen.
    func loadModels(_ p: ProviderID) {
        guard let provider = providers[p] else { return }
        settingsModel?.catalogs[p] = .loading
        Task { @MainActor in
            let state: ModelCatalogState
            do {
                state = .loaded(try await provider.availableModels())
            } catch let f as ProviderFailure {
                state = .failed(f.userMessage)
            } catch {
                state = .failed("The runtime didn't answer.")
            }
            self.settingsModel?.catalogs[p] = state
            if case .loaded(let m) = state { self.log.info("models \(p.rawValue, privacy: .public): \(m.count, privacy: .public)") }
        }
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

}
#endif
