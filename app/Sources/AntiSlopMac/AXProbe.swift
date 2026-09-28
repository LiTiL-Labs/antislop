#if os(macOS)
import AntiSlopCore
import AppKit
import ApplicationServices

/// Real-app check of capture and replacement against TextEdit (the documented
/// baseline: an AppKit NSTextView in a plain-text document). It uses the same
/// AccessibilityCapture/AccessibilityReplacer code as the app. Synthetic text
/// only; prints a JSON report. Requires Accessibility permission for the
/// process that runs it.
///
///   antislop-axprobe textedit [--out report.json] [--allow-quit-textedit] [--force]
///   antislop-axprobe e2e --app build/Anti-slop.app [--out report.json] [--shots dir]
///   antislop-axprobe e2e --app build/Anti-slop.app --live --provider claude-code|codex
///     (live: the real app and your signed-in provider; synthetic TextEdit text only)
@MainActor
public enum AXProbe {
    struct Check: Codable {
        let id: String
        let passed: Bool
        let detail: String
    }

    static var checks: [Check] = []

    static func record(_ id: String, _ passed: Bool, _ detail: String) {
        checks.append(Check(id: id, passed: passed, detail: detail))
        print("\(passed ? "PASS" : "FAIL") \(id): \(detail)")
    }

    static let original = "Intro sentence stays. It is worth noting that the pilot may reduce errors for some teams. Closing sentence stays.\n"
    static let target = "It is worth noting that the pilot may reduce errors for some teams."
    static let replacement = "The pilot may reduce errors for some teams."

    public static func run(_ args: [String]) async -> Int32 {
        let mode = args.dropFirst().first ?? "textedit"
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let out = value("--out")
        let trusted = AX.trusted(prompt: false)
        record("accessibility_trusted", trusted, trusted ? "process is trusted" : "grant Accessibility to the process running the probe")
        guard trusted else { return finish(out, code: 3) }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit")
        if !running.isEmpty && !args.contains("--force") {
            print("TextEdit is already running. Quit it (saving your documents) or pass --force.")
            return finish(out, code: 4)
        }
        switch mode {
        case "e2e":
            guard let app = value("--app") else { print("--app <path to Anti-slop.app> required"); return 2 }
            if args.contains("--live") {
                guard let p = value("--provider").flatMap(ProviderID.init(rawValue:)) else {
                    print("--live needs --provider claude-code or --provider codex")
                    return 2
                }
                await endToEnd(appPath: app, shots: value("--shots"), liveProvider: p)
            } else {
                await endToEnd(appPath: app, shots: value("--shots"), liveProvider: nil)
            }
        default:
            await textEditChecks(allowQuit: args.contains("--allow-quit-textedit"))
        }
        let failed = checks.contains { !$0.passed }
        return finish(out, code: failed ? 1 : 0)
    }

    static func finish(_ out: String?, code: Int32) -> Int32 {
        struct Report: Codable {
            let macOS: String
            let generatedAt: String
            let baseline: String
            let checks: [Check]
        }
        let report = Report(macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                            generatedAt: ISO8601DateFormatter().string(from: Date()),
                            baseline: "TextEdit plain-text document (AppKit NSTextView)", checks: checks)
        if let out, let data = try? JSONEncoder.pretty.encode(report) {
            try? data.write(to: URL(fileURLWithPath: out))
            print("wrote \(out)")
        }
        return code
    }

    // MARK: TextEdit helpers

    static func openDocument(named name: String, text: String) async -> (NSRunningApplication, AXUIElement)? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? Data(text.utf8).write(to: url)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "TextEdit", url.path]
        try? p.run()
        p.waitUntilExit()
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else { continue }
            app.activate(options: [])
            if let el = AX.focusedElement(ofApp: app.processIdentifier), AX.string(el, "AXValue") == text {
                return (app, el)
            }
        }
        return nil
    }

    static func select(_ el: AXUIElement, _ substring: String, in text: String) -> CFRange {
        let r = (text as NSString).range(of: substring)
        let cf = CFRange(location: r.location, length: r.length)
        _ = AX.setRange(el, "AXSelectedTextRange", cf)
        return cf
    }

    static func waitFrontmost(_ app: NSRunningApplication) async {
        app.activate(options: [])
        for _ in 0..<40 where NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    static func textEditChecks(allowQuit: Bool) async {
        guard let (app, el) = await openDocument(named: "anti-slop-probe-a.txt", text: original) else {
            record("open_textedit", false, "TextEdit document did not become focused")
            return
        }
        record("open_textedit", true, "TextEdit pid \(app.processIdentifier), role \(AX.string(el, "AXRole") ?? "?")")
        let capturer = AccessibilityCapture()
        let replacer = AccessibilityReplacer()

        // A12: exact selection, bounded context and bounds captured before any focus change.
        await waitFrontmost(app)
        _ = select(el, target, in: original)
        guard case .success(let snap) = capturer.captureFocusedSelection() else {
            record("capture", false, "capture refused")
            return
        }
        record("capture_exact_selection", snap.captured.selectedText == target, "selected text matched: \(snap.captured.selectedText == target)")
        record("capture_context", snap.captured.context.before == .excerpt("Intro sentence stays. ")
               && snap.captured.context.after == .excerpt(" Closing sentence stays.\n"),
               "before=\(snap.captured.context.before.boundary.rawValue) after=\(snap.captured.context.after.boundary.rawValue)")
        record("capture_bounds", snap.selectionBounds != nil, snap.selectionBounds.map { "w=\(Int($0.width)) h=\(Int($0.height))" } ?? "no bounds")
        record("capture_source_hint", snap.captured.sourceHint.appName == "TextEdit",
               "app=\(snap.captured.sourceHint.appName ?? "nil") title=\(snap.captured.sourceHint.documentTitle ?? "nil") type=\(snap.captured.sourceHint.contentTypeHint ?? "nil")")

        // A30: verified replacement of only the selection.
        let outcome = await replacer.replace(snap, with: replacement)
        let expected = original.replacingOccurrences(of: target, with: replacement)
        let after = AX.string(el, "AXValue")
        record("replace_confirmed", outcome == .confirmed(.accessibilitySelectedText), "outcome=\(outcome)")
        record("replace_surroundings_intact", after == expected, "document equals expected: \(after == expected)")

        // A33: native undo after an accessibility write.
        await waitFrontmost(app)
        KeyboardEvents.postCommand(KeyboardEvents.zKey, to: nil)
        try? await Task.sleep(nanoseconds: 600_000_000)
        let undone = AX.string(el, "AXValue")
        record("undo_restores_original", undone == original,
               undone == original ? "Cmd-Z restored the original" : "after Cmd-Z the document \(undone == expected ? "still holds the replacement" : "differs")")
        if undone != original { _ = AX.set(el, "AXValue", original as CFString) }

        // A29: moved selection blocks the write.
        await waitFrontmost(app)
        _ = select(el, target, in: original)
        if case .success(let s2) = capturer.captureFocusedSelection() {
            _ = select(el, "Closing sentence", in: original)
            let o = await replacer.replace(s2, with: replacement)
            record("drift_selection_blocks", o == .blocked(.selectionChanged) && AX.string(el, "AXValue") == original, "outcome=\(o)")
        } else { record("drift_selection_blocks", false, "capture failed") }

        // A29: text edited elsewhere in the document blocks the write.
        _ = select(el, target, in: original)
        if case .success(let s3) = capturer.captureFocusedSelection() {
            _ = select(el, "Closing", in: original)
            _ = AX.set(el, "AXSelectedText", "Final" as CFString)
            let edited = original.replacingOccurrences(of: "Closing", with: "Final")
            _ = select(el, target, in: edited)
            let o = await replacer.replace(s3, with: replacement)
            record("drift_text_blocks", o == .blocked(.textChanged) && AX.string(el, "AXValue") == edited, "outcome=\(o)")
            _ = AX.set(el, "AXValue", original as CFString)
        } else { record("drift_text_blocks", false, "capture failed") }

        // A29: another field gaining focus blocks the write; nothing is pasted there.
        _ = select(el, target, in: original)
        if case .success(let s4) = capturer.captureFocusedSelection() {
            let other = "Unrelated document.\n"
            if let (_, elB) = await openDocument(named: "anti-slop-probe-b.txt", text: other) {
                let o = await replacer.replace(s4, with: replacement)
                let bIntact = AX.string(elB, "AXValue") == other
                let aIntact = AX.string(el, "AXValue") == original
                record("drift_focus_blocks", (o == .blocked(.focusMoved) || o == .blocked(.elementGone)) && bIntact && aIntact,
                       "outcome=\(o) unrelated intact=\(bIntact) original intact=\(aIntact)")
                if let win = AX.element(elB, "AXWindow") {
                    AXUIElementPerformAction(win, "AXRaise" as CFString)
                }
                if let winA = AX.element(el, "AXWindow") {
                    AXUIElementPerformAction(winA, "AXRaise" as CFString)
                    _ = AX.set(winA, "AXMain", kCFBooleanTrue)
                }
            } else { record("drift_focus_blocks", false, "second document did not open") }
        } else { record("drift_focus_blocks", false, "capture failed") }

        // A32 (real clipboard): paste fallback restores the user's clipboard only when still owned.
        await waitFrontmost(app)
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let focused = AX.focusedElement(ofApp: app.processIdentifier), CFEqual(focused, el) {
            _ = select(el, target, in: original)
            let sentinel = "SENTINEL-\(UUID().uuidString)"
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(sentinel, forType: .string)
            if case .success(let s5) = capturer.captureFocusedSelection() {
                let o = await AccessibilityReplacer(method: .pasteboardOnly).replace(s5, with: replacement)
                let doc = AX.string(el, "AXValue")
                record("paste_fallback_confirmed", o == .confirmed(.pasteboard) && doc == expected, "outcome=\(o)")
                record("paste_fallback_restores_clipboard", pb.string(forType: .string) == sentinel,
                       "clipboard restored: \(pb.string(forType: .string) == sentinel)")
                _ = AX.set(el, "AXValue", original as CFString)
            } else { record("paste_fallback_confirmed", false, "capture failed") }
        } else {
            record("paste_fallback_confirmed", false, "could not refocus the first document")
        }

        // A29: the original app closing blocks the write.
        if allowQuit {
            _ = select(el, target, in: original)
            if case .success(let s6) = capturer.captureFocusedSelection() {
                app.forceTerminate()
                for _ in 0..<40 where !app.isTerminated { try? await Task.sleep(nanoseconds: 100_000_000) }
                let o = await replacer.replace(s6, with: replacement)
                record("app_closed_blocks", o == .blocked(.appClosed), "outcome=\(o)")
            }
        }
    }

    // MARK: Full app, fixture provider

    static func endToEnd(appPath: String, shots: String?, liveProvider: ProviderID?) async {
        if let shots { try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true) }
        func shot(_ name: String, window: Bool = true, pid: pid_t) {
            guard let shots else { return }
            let path = (shots as NSString).appendingPathComponent(name)
            if window, let id = frontWindowID(pid: pid) { capture(path, windowID: id) } else { capture(path, windowID: nil) }
        }
        let settingsURL = FileManager.default.temporaryDirectory.appendingPathComponent("anti-slop-e2e-settings.json")
        // ⌃⌥⌘J: a combination with no default system meaning.
        let shortcut = ShortcutBinding(keyCode: 0x26, displayLabel: "⌃⌥⌘J", modifiers: [.control, .option, .command])
        try? SettingsStore(fileURL: settingsURL).save(AppSettings(providerID: liveProvider ?? .claudeCode, shortcut: shortcut,
                                                                   customWriterInstructions: "Keep it measured."))
        let exe = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/MacOS/AntiSlop")
        let proc = Process()
        proc.executableURL = exe
        var env = ProcessInfo.processInfo.environment
        env["ANTISLOP_SETTINGS_PATH"] = settingsURL.path
        if let shots, liveProvider == nil { env["ANTISLOP_SNAPSHOT_DIR"] = shots }
        if liveProvider == nil {
            env["ANTISLOP_FIXTURE_PROVIDER"] = "1"
        } else {
            env.removeValue(forKey: "ANTISLOP_FIXTURE_PROVIDER")
        }
        proc.environment = env
        do { try proc.run() } catch {
            record("e2e_launch", false, "could not launch \(exe.path)")
            return
        }
        defer { proc.terminate() }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        record("e2e_launch", proc.isRunning, "Anti-slop pid \(proc.processIdentifier)")

        // A fresh document per run, so a previous run's edited window is never reused.
        let docName = "anti-slop-e2e-\(UUID().uuidString.prefix(8)).txt"
        guard let (app, el) = await openDocument(named: docName, text: original) else {
            record("e2e_textedit", false, "TextEdit document did not become focused")
            return
        }
        await waitFrontmost(app)
        _ = select(el, target, in: original)
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Escape cancels without changing the source (A27).
        KeyboardEvents.postChord(keyCode: 0x26, flags: [.maskControl, .maskAlternate, .maskCommand])
        let appeared = await waitForWindow(pid: proc.processIdentifier)
        record("e2e_panel_appears", appeared, appeared ? "panel window visible" : "no panel window")
        if liveProvider == nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
            shot("panel-processing.png", pid: proc.processIdentifier)
        }
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        if liveProvider == nil {
            shot("panel-ready.png", pid: proc.processIdentifier)
            shot("screen-ready.png", window: false, pid: proc.processIdentifier)
        }
        KeyboardEvents.postChord(keyCode: 0x35, flags: [])
        try? await Task.sleep(nanoseconds: 800_000_000)
        record("e2e_escape_no_change", AX.string(el, "AXValue") == original, "document unchanged after Escape")

        // Trigger again and apply with Command-Return (A28/A30).
        await waitFrontmost(app)
        _ = select(el, target, in: original)
        try? await Task.sleep(nanoseconds: 300_000_000)
        KeyboardEvents.postChord(keyCode: 0x26, flags: [.maskControl, .maskAlternate, .maskCommand])
        _ = await waitForWindow(pid: proc.processIdentifier)
        if let live = liveProvider {
            await liveApply(appPID: proc.processIdentifier, textEdit: el, provider: live,
                            shoot: { name in shot(name, pid: proc.processIdentifier) })
            return
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        KeyboardEvents.postChord(keyCode: 0x24, flags: [.maskCommand])
        var applied = false
        let expected = original.replacingOccurrences(of: target, with: replacement)
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if AX.string(el, "AXValue") == expected { applied = true; break }
        }
        record("e2e_apply_replaces_selection", applied, applied ? "fixture draft replaced only the selection" : "document not replaced")
        try? await Task.sleep(nanoseconds: 500_000_000)
        record("e2e_panel_closes_after_apply", !(await isPanelVisible(pid: proc.processIdentifier)), "panel dismissed after confirmed replacement")

        // A01/A02: with no key assigned, launch opens the same settings screen.
        proc.terminate()
        proc.waitUntilExit()
        try? SettingsStore(fileURL: settingsURL).save(AppSettings(providerID: .claudeCode))
        let again = Process()
        again.executableURL = exe
        again.environment = env
        if (try? again.run()) != nil {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let settingsShown = frontWindowID(pid: again.processIdentifier, normalLayer: true) != nil
            record("e2e_settings_without_key", settingsShown, "settings window opened on launch with no key assigned")
            if let shots, let id = frontWindowID(pid: again.processIdentifier, normalLayer: true) {
                capture((shots as NSString).appendingPathComponent("settings.png"), windowID: id)
            }
            again.terminate()
        }
    }

    static func windows(pid: pid_t) -> [[String: Any]] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
    }

    static func frontWindowID(pid: pid_t, normalLayer: Bool = false) -> CGWindowID? {
        let match = windows(pid: pid).first { w in
            let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
            return normalLayer ? layer == 0 : layer > 0 && layer < 20
        }
        return (match?[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) }
    }

    static func isPanelVisible(pid: pid_t) async -> Bool {
        frontWindowID(pid: pid) != nil
    }

    /// Live provider: wait for a real proposal in the panel's editor, apply it,
    /// and verify that only the selected sentence changed.
    static func liveApply(appPID: pid_t, textEdit el: AXUIElement, provider: ProviderID, shoot: (String) -> Void) async {
        var proposal: String? = nil
        for _ in 0..<(Int(Limits.rewriteTimeout) * 2 + 20) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let text = panelEditorText(pid: appPID), !text.isEmpty { proposal = text; break }
        }
        guard let proposal else {
            // The panel's own status or failure message says why (app-authored text only).
            let shown = panelStaticTexts(pid: appPID).joined(separator: " | ")
            record("live_proposal", false, "no proposal appeared in the panel; it shows: \(shown.isEmpty ? "(no panel text)" : shown)")
            shoot("live-panel-failed.png")
            return
        }
        record("live_proposal", true, "\(provider.displayName) proposal: \(proposal)")
        shoot("live-panel-ready.png")
        KeyboardEvents.postChord(keyCode: 0x24, flags: [.maskCommand])
        let head = "Intro sentence stays. ", tail = " Closing sentence stays.\n"
        var final: String? = nil
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let v = AX.string(el, "AXValue"), v != original { final = v; break }
        }
        guard let final else {
            record("live_apply_replaces_selection", false, "document unchanged after apply")
            return
        }
        let middle = String(final.dropFirst(head.count).dropLast(tail.count))
        let ok = final.hasPrefix(head) && final.hasSuffix(tail) && middle == proposal
        record("live_apply_replaces_selection", ok,
               ok ? "only the selection changed; it now reads: \(middle)" : "unexpected document: \(final)")
    }

    /// The panel's draft editor text, read through Accessibility.
    static func panelEditorText(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        guard let windows = AX.value(app, "AXWindows") as? [AXUIElement] else { return nil }
        for w in windows {
            if let text = findTextArea(w, depth: 0) { return text }
        }
        return nil
    }

    /// Visible static text in the app's windows, in tree order.
    static func panelStaticTexts(pid: pid_t) -> [String] {
        var out: [String] = []
        func walk(_ el: AXUIElement, _ depth: Int) {
            if depth > 12 || out.count >= 12 { return }
            if AX.string(el, "AXRole") == "AXStaticText", let v = AX.string(el, "AXValue"), !v.isBlank { out.append(v) }
            for c in (AX.value(el, "AXChildren") as? [AXUIElement]) ?? [] { walk(c, depth + 1) }
        }
        let app = AXUIElementCreateApplication(pid)
        for w in (AX.value(app, "AXWindows") as? [AXUIElement]) ?? [] { walk(w, 0) }
        return out
    }

    static func findTextArea(_ el: AXUIElement, depth: Int) -> String? {
        if depth > 12 { return nil }
        if AX.string(el, "AXRole") == "AXTextArea", let v = AX.string(el, "AXValue") { return v }
        guard let children = AX.value(el, "AXChildren") as? [AXUIElement] else { return nil }
        for c in children {
            if let v = findTextArea(c, depth: depth + 1) { return v }
        }
        return nil
    }

    static func waitForWindow(pid: pid_t) async -> Bool {
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if frontWindowID(pid: pid) != nil { return true }
        }
        return false
    }

    /// Screenshot of one window (with its shadow) or the whole screen.
    static func capture(_ path: String, windowID: CGWindowID?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = windowID.map { ["-x", "-l", String($0), path] } ?? ["-x", path]
        try? p.run()
        p.waitUntilExit()
        print("screenshot \(path) exit \(p.terminationStatus)")
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
#endif
