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

        // A14: a partial word and a span with boundary spaces are captured and replaced exactly.
        await waitFrontmost(app)
        _ = AX.set(el, "AXValue", original as CFString)
        var partialOK = true
        var partialDetail: [String] = []
        for (piece, with) in [("ilo", "ILO"), (" may reduce ", " might reduce ")] {
            let doc = AX.string(el, "AXValue") ?? ""
            _ = select(el, piece, in: doc)
            guard case .success(let s) = capturer.captureFocusedSelection(), s.captured.selectedText == piece else {
                partialOK = false
                partialDetail.append("\(piece.debugDescription): capture did not match")
                continue
            }
            let o = await replacer.replace(s, with: with)
            let expectedDoc = (doc as NSString).replacingCharacters(in: (doc as NSString).range(of: piece), with: with)
            let ok = o == .confirmed(.accessibilitySelectedText) && AX.string(el, "AXValue") == expectedDoc
            partialOK = partialOK && ok
            partialDetail.append("\(piece.debugDescription) → \(with.debugDescription): \(ok ? "exact splice" : "outcome=\(o)")")
        }
        record("partial_selection_exact", partialOK, partialDetail.joined(separator: "; "))
        _ = AX.set(el, "AXValue", original as CFString)

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
        let closedAfterApply = !(await isPanelVisible(pid: proc.processIdentifier))
        record("e2e_panel_closes_after_apply", closedAfterApply && proc.isRunning,
               "panel dismissed after confirmed replacement: \(closedAfterApply); app still running: \(proc.isRunning)")

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
            if settingsShown {
                await recorderChecks(pid: again.processIdentifier, settingsURL: settingsURL)
            }
            again.terminate()
            again.waitUntilExit()
        }
        await singleKeyChecks(exe: exe, env: env, settingsURL: settingsURL)
    }

    // MARK: Key assignment and panel editing (fixture provider)

    /// A04/A05 on the real settings screen: record a combination, refuse an
    /// invalid one and cancel a recording without losing it; Done saves and
    /// registers the new key, which then triggers the panel.
    static func recorderChecks(pid: pid_t, settingsURL: URL) async {
        let app = probeElement(pid)
        func press(_ label: String) async -> Bool {
            var ok = false
            if let b = findPressable(app, label) {
                ok = AXUIElementPerformAction(b, "AXPress" as CFString) == .success
            } else if let t = findElement(app, { elementTexts($0, depth: 0).contains(label) }), let f = frame(of: t) {
                KeyboardEvents.click(at: CGPoint(x: f.midX, y: f.midY))
                ok = true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            return ok
        }
        func screenText() -> String { elementTexts(app, depth: 30).joined(separator: " | ") }
        func currentKey() -> String {
            elementTexts(app, depth: 30).first { $0.hasPrefix("Current key:") } ?? "(no current-key label)"
        }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        try? await Task.sleep(nanoseconds: 500_000_000)

        guard await press("Assign anti-slop key") else {
            record("recorder_records_combination", false, "no Assign anti-slop key button; screen shows: \(screenText().prefix(300))")
            return
        }
        KeyboardEvents.postChord(keyCode: 0x28, flags: [.maskControl, .maskAlternate, .maskCommand]) // ⌃⌥⌘K
        try? await Task.sleep(nanoseconds: 600_000_000)
        let recorded = screenText().contains("K is ready to use after you choose Done.")
        record("recorder_records_combination", recorded && currentKey().contains("K"),
               "\(currentKey()); message shown: \(recorded)")

        // Fn/Globe combinations can't be registered on macOS: specific feedback, previous key kept.
        _ = await press("Assign anti-slop key")
        KeyboardEvents.postChord(keyCode: 0x26, flags: [.maskSecondaryFn])
        try? await Task.sleep(nanoseconds: 600_000_000)
        let refused = screenText().contains("Fn/Globe")
        record("recorder_refuses_invalid_keeps_previous", refused && currentKey().contains("K"),
               "\(currentKey()); Fn/Globe explanation shown: \(refused)")

        _ = await press("Assign anti-slop key")
        let cancelled = await press("Cancel")
        record("recorder_cancel_keeps_previous", cancelled && currentKey().contains("K"),
               "Cancel pressed: \(cancelled); \(currentKey())")

        let done = await press("Done")
        try? await Task.sleep(nanoseconds: 700_000_000)
        var saved = "unreadable"
        if case .loaded(let s) = SettingsStore(fileURL: settingsURL).load(), let k = s.shortcut {
            saved = "key_code \(k.keyCode) modifiers \(k.modifiers.map(\.rawValue).sorted())"
        }
        record("done_saves_new_key", done && saved == "key_code 40 modifiers [\"command\", \"control\", \"option\"]",
               "Done pressed: \(done); settings file has \(saved)")

        let docName = "anti-slop-recorder-\(UUID().uuidString.prefix(8)).txt"
        guard let (textEdit, el) = await openDocument(named: docName, text: original) else {
            record("new_key_triggers", false, "TextEdit document did not become focused")
            return
        }
        await waitFrontmost(textEdit)
        _ = select(el, target, in: original)
        try? await Task.sleep(nanoseconds: 300_000_000)
        KeyboardEvents.postChord(keyCode: 0x28, flags: [.maskControl, .maskAlternate, .maskCommand])
        let appeared = await waitForWindow(pid: pid)
        record("new_key_triggers", appeared, appeared ? "the newly assigned ⌃⌥⌘K opened the panel" : "no panel after ⌃⌥⌘K")
        // Let the panel reach Ready before closing it, so any self-rendered snapshot shows a settled panel.
        _ = await waitForEditorText(pid: pid)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        KeyboardEvents.postChord(keyCode: 0x35, flags: [])
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    /// A03/A06/A28 with an unmodified single key (`) as the trigger: holding it
    /// opens one panel and types nothing; inside the panel the key types
    /// normally and Return adds a newline; an empty draft can't be applied; the
    /// edited draft is applied once; the key triggers again afterwards.
    static func singleKeyChecks(exe: URL, env: [String: String], settingsURL: URL) async {
        let grave: CGKeyCode = 0x32
        try? SettingsStore(fileURL: settingsURL).save(AppSettings(
            providerID: .claudeCode, shortcut: ShortcutBinding(keyCode: Int(grave), displayLabel: "`", modifiers: [])))
        let proc = Process()
        proc.executableURL = exe
        // No self-rendered snapshots here: edits would overwrite the ready-panel image.
        proc.environment = env.filter { $0.key != "ANTISLOP_SNAPSHOT_DIR" }
        guard (try? proc.run()) != nil else {
            record("single_key_triggers", false, "could not launch \(exe.path)")
            return
        }
        defer { proc.terminate() }
        let pid = proc.processIdentifier
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        let docName = "anti-slop-keys-\(UUID().uuidString.prefix(8)).txt"
        guard let (app, el) = await openDocument(named: docName, text: original) else {
            record("single_key_triggers", false, "TextEdit document did not become focused")
            return
        }
        await waitFrontmost(app)
        _ = select(el, target, in: original)
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Hold the key: press, auto-repeat after the usual delay, release.
        KeyboardEvents.postKey(grave, down: true)
        try? await Task.sleep(nanoseconds: 500_000_000)
        for _ in 0..<6 {
            KeyboardEvents.postKey(grave, down: true, autorepeat: true)
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        KeyboardEvents.postKey(grave, down: false)
        let appeared = await waitForWindow(pid: pid)
        let draft = await waitForEditorText(pid: pid)
        let untouched = AX.string(el, "AXValue") == original
        record("single_key_triggers", appeared && untouched,
               appeared ? "unmodified ` opened the panel; the document received no character: \(untouched)" : "no panel")
        let panels = windows(pid: pid).filter { w in
            let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
            return layer > 0 && layer < 20
        }.count
        record("held_key_one_activation", draft == replacement && panels == 1,
               "\(panels) panel window(s); draft: \(draft?.debugDescription ?? "none")")

        // A06/A28: inside the panel the assigned key types normally and Return adds a newline.
        KeyboardEvents.postChord(keyCode: 0x00, flags: .maskCommand) // ⌘A in the editor
        try? await Task.sleep(nanoseconds: 200_000_000)
        KeyboardEvents.typeText("Edited by hand")
        KeyboardEvents.postChord(keyCode: grave, flags: [])
        KeyboardEvents.postChord(keyCode: 0x24, flags: [])
        KeyboardEvents.typeText("second line.")
        try? await Task.sleep(nanoseconds: 600_000_000)
        let edited = panelEditorText(pid: pid) ?? ""
        let expectedEdit = "Edited by hand`\nsecond line."
        let stillOriginal = AX.string(el, "AXValue") == original
        let editFocus = await focusReport(pid: pid)
        record("assigned_key_types_in_panel", edited.hasPrefix("Edited by hand`") && stillOriginal,
               "editor reads \(edited.debugDescription); document unchanged: \(stillOriginal); \(editFocus)")
        record("return_inserts_newline", edited == expectedEdit && stillOriginal,
               "Return added a newline and did not apply: \(edited == expectedEdit && stillOriginal)")

        // A28/A30: the edited draft is applied once, only over the selection.
        KeyboardEvents.postChord(keyCode: 0x24, flags: .maskCommand)
        var final: String? = nil
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let v = AX.string(el, "AXValue"), v != original { final = v; break }
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let expectedDoc = original.replacingOccurrences(of: target, with: expectedEdit)
        let settled = AX.string(el, "AXValue")
        record("edited_draft_applied_once", final == expectedDoc && settled == expectedDoc,
               final == expectedDoc ? "document now holds the edited draft exactly once" : "document: \(settled.debugDescription)")
        let closedAfterEdit = !(await isPanelVisible(pid: pid))
        record("panel_closes_after_edited_apply", closedAfterEdit && proc.isRunning,
               "panel dismissed after confirmed replacement: \(closedAfterEdit); app still running: \(proc.isRunning)")

        // A06: with Anti-slop inactive again, the key is registered again.
        await waitFrontmost(app)
        let now = AX.string(el, "AXValue") ?? ""
        _ = select(el, "Closing sentence stays.", in: now)
        try? await Task.sleep(nanoseconds: 300_000_000)
        KeyboardEvents.postChord(keyCode: grave, flags: [])
        let again = await waitForWindow(pid: pid)
        _ = await waitForEditorText(pid: pid)
        let afterPress = AX.string(el, "AXValue") ?? ""
        record("key_triggers_again_after_panel", again && afterPress == now,
               again ? "` opened the panel again; the document received no character"
                     : "no panel on the second press; the key \(afterPress == now ? "was consumed" : "reached TextEdit")")

        // A28: an empty editor can't be applied, and typing continues in the editor afterwards.
        KeyboardEvents.postChord(keyCode: 0x00, flags: .maskCommand)
        KeyboardEvents.postChord(keyCode: 0x33, flags: [])           // Delete
        try? await Task.sleep(nanoseconds: 300_000_000)
        let emptied = panelEditorText(pid: pid) ?? "(no editor)"
        KeyboardEvents.postChord(keyCode: 0x24, flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 800_000_000)
        let panelOpen = await isPanelVisible(pid: pid)
        let blankKept = AX.string(el, "AXValue") == now && emptied.isEmpty && panelOpen
        record("blank_draft_not_applied", blankKept,
               "editor before ⌘Return \(emptied.debugDescription); document unchanged and panel open: \(blankKept); panel says: \(panelStaticTexts(pid: pid).joined(separator: " | "))")
        KeyboardEvents.typeText("Kept typing.")
        try? await Task.sleep(nanoseconds: 500_000_000)
        let afterBlank = panelEditorText(pid: pid) ?? "(no editor)"
        let stillOpen = await isPanelVisible(pid: pid)
        let blankFocus = await focusReport(pid: pid)
        record("typing_continues_after_blocked_apply", afterBlank == "Kept typing." && stillOpen,
               "editor reads \(afterBlank.debugDescription); \(blankFocus)")
        KeyboardEvents.postChord(keyCode: 0x35, flags: [])
        try? await Task.sleep(nanoseconds: 600_000_000)
        let closedByEscape = !(await isPanelVisible(pid: pid))
        record("escape_after_edits_no_change", AX.string(el, "AXValue") == now && closedByEscape,
               "Escape closed the panel: \(closedByEscape); document unchanged: \(AX.string(el, "AXValue") == now)")
    }

    /// Where keyboard input is going: frontmost app, the app's focused element, panel visibility.
    static func focusReport(pid: pid_t) async -> String {
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let app = probeElement(pid)
        let focused = AX.element(app, "AXFocusedUIElement")
        let role = focused.flatMap { AX.string($0, "AXRole") } ?? "none"
        let label = focused.flatMap { AX.string($0, "AXDescription") ?? AX.string($0, "AXTitle") } ?? ""
        let visible = await isPanelVisible(pid: pid)
        return "frontmost \(front); Anti-slop focus \(role) \(label.debugDescription); panel visible \(visible)"
    }

    static func waitForEditorText(pid: pid_t, seconds: Double = 6) async -> String? {
        for _ in 0..<Int(seconds * 10) {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let t = panelEditorText(pid: pid), !t.isEmpty { return t }
        }
        return nil
    }

    /// Text an element exposes (value, title, description), with its descendants', in tree order.
    static func elementTexts(_ root: AXUIElement, depth: Int) -> [String] {
        var out: [String] = []
        func walk(_ el: AXUIElement, _ d: Int) {
            for attr in ["AXValue", "AXTitle", "AXDescription"] {
                if let s = AX.string(el, attr), !s.isBlank { out.append(s) }
            }
            guard d < depth else { return }
            for c in (AX.value(el, "AXChildren") as? [AXUIElement]) ?? [] { walk(c, d + 1) }
        }
        walk(root, 0)
        return out
    }

    /// The app's Accessibility element with a short messaging timeout, so an
    /// unresponsive app fails a check quickly instead of stalling the probe.
    static func probeElement(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 1.0)
        return el
    }

    static func actionNames(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }

    /// The innermost element that can be pressed and shows `label`.
    static func findPressable(_ root: AXUIElement, _ label: String, depth: Int = 0) -> AXUIElement? {
        guard depth < 30 else { return nil }
        for c in (AX.value(root, "AXChildren") as? [AXUIElement]) ?? [] {
            if let hit = findPressable(c, label, depth: depth + 1) { return hit }
        }
        if actionNames(root).contains("AXPress"), elementTexts(root, depth: 3).contains(label) { return root }
        return nil
    }

    /// Screen frame (top-left origin, as CGEvent uses) of an element.
    static func frame(of el: AXUIElement) -> CGRect? {
        guard let pv = AX.value(el, "AXPosition"), let sv = AX.value(el, "AXSize"),
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: p, size: sz)
    }

    static func findElement(_ root: AXUIElement, _ match: (AXUIElement) -> Bool, depth: Int = 0) -> AXUIElement? {
        if match(root) { return root }
        guard depth < 30 else { return nil }
        for c in (AX.value(root, "AXChildren") as? [AXUIElement]) ?? [] {
            if let hit = findElement(c, match, depth: depth + 1) { return hit }
        }
        return nil
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
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let closed = !(await isPanelVisible(pid: appPID))
        let alive = kill(appPID, 0) == 0
        record("live_panel_closes_app_keeps_running", closed && alive,
               "panel dismissed: \(closed); Anti-slop still running: \(alive)")
    }

    /// The panel's draft editor text, read through Accessibility.
    static func panelEditorText(pid: pid_t) -> String? {
        let app = probeElement(pid)
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
        let app = probeElement(pid)
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
