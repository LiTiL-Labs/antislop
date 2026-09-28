import XCTest
@testable import AntiSlopCore

func rewrite(_ text: String, intent: String = "Looks like an update", note: String? = nil) -> ProviderRewrite {
    ProviderRewrite(response: RewriteResponse(intent: intent, rewrittenText: text, note: note),
                    receipt: ProviderReceipt(provider: "test", runtimeVersion: "0", model: nil, durationMs: 1, profile: "none", outcome: "ok"))
}

final class RewriteSessionTests: XCTestCase {
    func makeSession(_ text: String = "It is worth noting that the pilot may help.") -> RewriteSession {
        RewriteSession(capture: capture(text))
    }

    /// A26: user edits remain; delayed or stale provider events are discarded.
    func testLateResultsNeverOverwriteUserEdits() {
        let s = makeSession()
        let g1 = s.beginGeneration()!
        XCTAssertTrue(s.receive(rewrite("The pilot may help."), generation: g1))
        s.edit("The pilot may help a lot.")
        XCTAssertTrue(s.userHasEdited)
        XCTAssertFalse(s.receive(rewrite("OVERWRITE"), generation: g1))
        XCTAssertEqual(s.draft, "The pilot may help a lot.")
        XCTAssertNil(s.beginGeneration(), "no regeneration over user edits")
    }

    func testStaleGenerationAfterRetryIsIgnored() {
        let s = makeSession()
        let g1 = s.beginGeneration()!
        XCTAssertTrue(s.receive(failure: .offline(.codex), generation: g1))
        let g2 = s.beginGeneration()!
        XCTAssertFalse(s.receive(rewrite("from g1"), generation: g1))
        XCTAssertTrue(s.receive(rewrite("from g2"), generation: g2))
        XCTAssertEqual(s.draft, "from g2")
    }

    /// A27: cancellation blocks late results.
    func testCancelBlocksLateResults() {
        let s = makeSession()
        let g = s.beginGeneration()!
        s.cancel()
        XCTAssertEqual(s.phase, .cancelled)
        XCTAssertFalse(s.receive(rewrite("late"), generation: g))
        XCTAssertFalse(s.receive(failure: .timedOut(.claudeCode), generation: g))
        XCTAssertEqual(s.phase, .cancelled)
        XCTAssertNil(s.beginApply())
    }

    /// A25 / A28: apply disabled while generating; blank draft blocked with feedback; one submission.
    func testApplyGuards() {
        let s = makeSession()
        let g = s.beginGeneration()!
        XCTAssertEqual(s.applyAvailability, .disabled(reason: nil))
        XCTAssertNil(s.beginApply())
        s.receive(rewrite("The pilot may help."), generation: g)
        XCTAssertEqual(s.applyAvailability, .enabled)
        s.edit("   \n  ")
        XCTAssertEqual(s.applyAvailability, .disabled(reason: "Enter replacement text to apply."))
        XCTAssertNil(s.beginApply(), "blank draft rejected immediately before mutation")
        s.edit("The pilot may help, edited.")
        XCTAssertEqual(s.beginApply(), "The pilot may help, edited.", "final edited contents are used")
        XCTAssertNil(s.beginApply(), "no duplicate submission")
        XCTAssertEqual(s.phase, .applying)
        s.edit("changed during apply")
        XCTAssertEqual(s.draft, "The pilot may help, edited.", "draft frozen while applying")
        s.finishApply(.confirmed(.accessibilitySelectedText))
        XCTAssertEqual(s.phase, .succeeded)
    }

    /// A29 / A31: target change keeps the draft; uncertain completion never re-enables apply.
    func testTargetChangeAndUncertainOutcomes() {
        let s = makeSession()
        let g = s.beginGeneration()!
        s.receive(rewrite("Draft."), generation: g)
        _ = s.beginApply()
        s.finishApply(.blocked(.selectionChanged))
        XCTAssertEqual(s.phase, .targetChanged(.selectionChanged))
        XCTAssertEqual(s.draft, "Draft.")
        XCTAssertEqual(s.applyAvailability, .disabled(reason: nil))
        s.returnToReadyAfterTargetChange()
        XCTAssertNotNil(s.beginApply(), "nothing was written, so one explicit retry is safe")
        s.finishApply(.uncertain("verification unavailable"))
        XCTAssertEqual(s.phase, .failed(.applyUncertain("verification unavailable")))
        XCTAssertNil(s.beginApply())
        XCTAssertEqual(s.draft, "Draft.")
    }

    func testUnchangedProposalIsValidAndIntentIsOneLine() {
        let s = makeSession("Already clear.")
        let g = s.beginGeneration()!
        s.receive(rewrite("Already clear.", intent: "Looks like\na note"), generation: g)
        XCTAssertTrue(s.isUnchangedProposal)
        XCTAssertEqual(s.intentLine, "Looks like a note")
        XCTAssertEqual(s.applyAvailability, .enabled)
    }

    func testPlaceholderNotesAreNotDisplayed() {
        for placeholder in ["None", " null ", "N/A"] {
            let s = makeSession("Text.")
            let g = s.beginGeneration()!
            s.receive(rewrite("Text.", note: placeholder), generation: g)
            XCTAssertNil(s.note, placeholder)
        }
        let s = makeSession("Text.")
        let g = s.beginGeneration()!
        s.receive(rewrite("Text.", note: "Kept the defined term."), generation: g)
        XCTAssertEqual(s.note, "Kept the defined term.")
    }
}

// MARK: - Coordinator with deterministic stubs

final class StubCapturer: SelectionCapturing {
    var result: Result<CaptureSnapshot, CaptureRefusal>
    var calls = 0
    init(_ r: Result<CaptureSnapshot, CaptureRefusal>) { result = r }
    func captureFocusedSelection() -> Result<CaptureSnapshot, CaptureRefusal> { calls += 1; return result }
}

final class StubReplacer: TextReplacing {
    var outcome: ApplyOutcome = .confirmed(.accessibilitySelectedText)
    var writes: [String] = []
    func replace(_ snapshot: CaptureSnapshot, with text: String) async -> ApplyOutcome {
        writes.append(text)
        return outcome
    }
}

func snapshot(_ text: String) -> CaptureSnapshot {
    CaptureSnapshot(captured: capture(text), target: TargetEvidence(processID: 42, selectedText: text), selectionBounds: nil, handle: nil)
}

@MainActor
final class CoordinatorTests: XCTestCase {
    var settings = AppSettings(providerID: .claudeCode)

    func make(_ provider: FixtureProvider, capturer: StubCapturer? = nil, replacer: StubReplacer = StubReplacer())
        -> (SessionCoordinator, StubCapturer, StubReplacer) {
        let cap = capturer ?? StubCapturer(.success(snapshot("It is worth noting that the pilot may reduce errors.")))
        let c = SessionCoordinator(capturer: cap, replacer: replacer, settings: { [unowned self] in self.settings },
                                   provider: { _ in provider }, timeout: 5)
        return (c, cap, replacer)
    }

    func waitFor(_ c: SessionCoordinator, _ predicate: @escaping (SessionPhase) -> Bool) async {
        for _ in 0..<200 {
            if let p = c.session?.phase, predicate(p) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting; phase=\(String(describing: c.session?.phase))")
    }

    func testHappyPathAppliesFinalEditedDraftOnce() async {
        let fixture = FixtureProvider(delay: 0.01)
        let (c, _, rep) = make(fixture)
        XCTAssertEqual(c.trigger(), .started)
        XCTAssertEqual(c.session?.phase, .generating)
        await waitFor(c) { $0 == .ready }
        XCTAssertEqual(c.session?.draft, "The pilot may reduce errors.")
        XCTAssertTrue(c.session?.usedFixture ?? false, "fixture output is labelled as such")
        c.edit("The pilot may reduce some errors.")
        await c.apply()
        await c.apply()
        XCTAssertEqual(rep.writes, ["The pilot may reduce some errors."])
        XCTAssertEqual(c.session?.phase, .succeeded)
    }

    /// A27: duplicate trigger focuses the existing panel; close cancels without mutation.
    func testDuplicateTriggerAndCancel() async {
        let fixture = FixtureProvider(behavior: .hang)
        let (c, cap, rep) = make(fixture)
        XCTAssertEqual(c.trigger(), .started)
        XCTAssertEqual(c.trigger(), .focusExisting)
        XCTAssertEqual(cap.calls, 1, "no second capture while active")
        c.cancel()
        XCTAssertEqual(c.session?.phase, .cancelled)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(c.session?.phase, .cancelled)
        XCTAssertTrue(rep.writes.isEmpty)
        XCTAssertEqual(c.trigger(), .started, "a new selection can start after cancel")
    }

    /// A11: refusals never reach a provider.
    func testCaptureRefusalMakesNoRequest() {
        let fixture = FixtureProvider()
        let (c, _, _) = make(fixture, capturer: StubCapturer(.failure(.secureField)))
        XCTAssertEqual(c.trigger(), .refused(.secureField))
        XCTAssertNil(c.session)
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    /// A16 / UX: settings are snapshotted per request; a change affects the next rewrite.
    func testSettingsChangeAffectsOnlyTheNextRequest() async {
        let fixture = FixtureProvider(delay: 0.05)
        settings.customWriterInstructions = "First preference."
        let (c, _, _) = make(fixture)
        _ = c.trigger()
        settings.customWriterInstructions = "Second preference."
        await waitFor(c) { $0 == .ready }
        let draft = c.session?.draft
        XCTAssertEqual(fixture.requests.last?.request.customWriterInstructions, "First preference.")
        XCTAssertEqual(c.session?.draft, draft, "no silent regeneration")
        c.clear()
        _ = c.trigger()
        await waitFor(c) { $0 == .ready }
        XCTAssertEqual(fixture.requests.last?.request.customWriterInstructions, "Second preference.")
    }

    /// A34: malformed output is never inserted and no provider switch happens.
    func testMalformedResponseIsNeverApplied() async {
        let fixture = FixtureProvider(behavior: .rawJSON("Sure! Here you go: {\"intent\":\"x\"}"), delay: 0.01)
        var asked: [ProviderID] = []
        let rep = StubReplacer()
        let c = SessionCoordinator(capturer: StubCapturer(.success(snapshot("Some text to edit."))), replacer: rep,
                                   settings: { AppSettings(providerID: .codex) },
                                   provider: { asked.append($0); return fixture }, timeout: 5)
        _ = c.trigger()
        await waitFor(c) { if case .failed = $0 { return true }; return false }
        XCTAssertEqual(c.session?.phase, .failed(.provider(.malformedResponse(.claudeCode, .notSingleObject))))
        XCTAssertFalse(c.session?.hasDraft ?? true)
        await c.apply()
        XCTAssertTrue(rep.writes.isEmpty)
        XCTAssertEqual(asked, [.codex], "the chosen provider is honored, never substituted")
    }

    func testRetryAfterFailureBeforeAnyEdit() async {
        let fixture = FixtureProvider(behavior: .fail(.offline(.claudeCode)), delay: 0.01)
        let (c, _, _) = make(fixture)
        _ = c.trigger()
        await waitFor(c) { if case .failed = $0 { return true }; return false }
        fixture.behavior = .lightEdit
        c.retry()
        await waitFor(c) { $0 == .ready }
        XCTAssertEqual(fixture.requests.count, 2)
    }

    /// A38: diagnostics never contain document text.
    func testDiagnosticsContainNoContent() async {
        let secret = "Confidential merger terms for Project Nightjar."
        let fixture = FixtureProvider(delay: 0.01)
        let rep = StubReplacer()
        let c = SessionCoordinator(capturer: StubCapturer(.success(snapshot(secret))), replacer: rep,
                                   settings: { AppSettings(providerID: .claudeCode, customWriterInstructions: "Secret style note") },
                                   provider: { _ in fixture }, timeout: 5)
        var lines: [String] = []
        c.diagnostics = { lines.append($0) }
        _ = c.trigger()
        await waitFor(c) { $0 == .ready }
        await c.apply()
        XCTAssertFalse(lines.isEmpty)
        for l in lines {
            XCTAssertFalse(l.contains("Nightjar") || l.contains("merger") || l.contains("Secret style"), l)
        }
    }

    /// A29: after drift, nothing is written until the user explicitly adopts a
    /// new selection and presses Anti-slop again; the draft is untouched.
    func testTargetChangeThenExplicitRetarget() async {
        let fixture = FixtureProvider(delay: 0.01)
        let rep = StubReplacer()
        rep.outcome = .blocked(.selectionChanged)
        let cap = StubCapturer(.success(snapshot("It is worth noting that the pilot may reduce errors.")))
        let (c, _, _) = make(fixture, capturer: cap, replacer: rep)
        _ = c.trigger()
        await waitFor(c) { $0 == .ready }
        c.edit("Edited draft.")
        await c.apply()
        XCTAssertEqual(c.session?.phase, .targetChanged(.selectionChanged))
        XCTAssertEqual(c.session?.draft, "Edited draft.")
        cap.result = .success(snapshot("A different selection."))
        XCTAssertNil(c.retarget())
        XCTAssertEqual(c.snapshot?.captured.selectedText, "A different selection.")
        XCTAssertEqual(c.session?.phase, .ready)
        XCTAssertEqual(fixture.requests.count, 1, "no regeneration")
        rep.outcome = .confirmed(.accessibilitySelectedText)
        await c.apply()
        XCTAssertEqual(rep.writes, ["Edited draft.", "Edited draft."])
        XCTAssertEqual(c.session?.phase, .succeeded)
    }

    func testFailedApplyRetainsDraft() async {
        let fixture = FixtureProvider(delay: 0.01)
        let rep = StubReplacer()
        rep.outcome = .failed("write rejected")
        let (c, _, _) = make(fixture, replacer: rep)
        _ = c.trigger()
        await waitFor(c) { $0 == .ready }
        c.edit("My careful edit.")
        await c.apply()
        XCTAssertEqual(c.session?.phase, .failed(.applyFailed("write rejected")))
        XCTAssertEqual(c.session?.draft, "My careful edit.")
    }
}

final class ReplacementPlannerTests: XCTestCase {
    let full = "Intro. It is worth noting that the pilot may reduce errors. Outro."
    var original: TargetEvidence {
        let r = (full as NSString).range(of: "It is worth noting that the pilot may reduce errors.")
        return TargetEvidence(processID: 7, bundleID: "com.apple.TextEdit", role: "AXTextArea", isEditable: true,
                              selectedText: "It is worth noting that the pilot may reduce errors.",
                              selectedRange: TextRange(location: r.location, length: r.length), fullText: full)
    }

    func obs(_ e: TargetEvidence?, running: Bool = true, same: Bool = true, focused: Bool = true) -> TargetObservation {
        TargetObservation(appIsRunning: running, isSameElement: same, isFocusedInApp: focused, evidence: e)
    }

    func testValidTargetPasses() {
        XCTAssertNil(ReplacementPlanner.check(original: original, now: obs(original)))
    }

    /// A29: any drift blocks the write.
    func testDriftBlocks() {
        XCTAssertEqual(ReplacementPlanner.check(original: original, now: obs(original, running: false)), .appClosed)
        XCTAssertEqual(ReplacementPlanner.check(original: original, now: obs(original, same: false)), .elementGone)
        XCTAssertEqual(ReplacementPlanner.check(original: original, now: obs(original, focused: false)), .focusMoved)
        var moved = original
        moved.selectedRange = TextRange(location: 0, length: 6)
        XCTAssertEqual(ReplacementPlanner.check(original: original, now: obs(moved)), .selectionChanged)
        var edited = original
        edited.fullText = full.replacingOccurrences(of: "Outro.", with: "Outro!")
        XCTAssertEqual(ReplacementPlanner.check(original: original, now: obs(edited)), .textChanged)
        var readOnly = original
        readOnly.isEditable = false
        XCTAssertEqual(ReplacementPlanner.check(original: original, now: obs(readOnly)), .notEditable)
        var secure = original
        secure.isSecure = true
        XCTAssertEqual(ReplacementPlanner.check(original: original, now: obs(secure)), .notEditable)
        var noText = original
        noText.fullText = nil
        XCTAssertEqual(ReplacementPlanner.check(original: original, now: obs(noText)), .evidenceUnavailable("text"))
        XCTAssertEqual(ReplacementPlanner.check(original: original, now: obs(nil)), .evidenceUnavailable("attributes"))
    }

    /// A30: only the original selection changes; surroundings are intact.
    func testVerification() {
        let replacement = "The pilot may reduce errors."
        let expected = ReplacementPlanner.expectedFullText(original: original, replacement: replacement)
        XCTAssertEqual(expected, "Intro. The pilot may reduce errors. Outro.")
        XCTAssertEqual(ReplacementPlanner.verify(original: original, replacement: replacement,
                                                 observedFullText: expected, observedRangeText: nil), .confirmed)
        XCTAssertEqual(ReplacementPlanner.verify(original: original, replacement: replacement,
                                                 observedFullText: full, observedRangeText: nil), .unchanged)
        XCTAssertEqual(ReplacementPlanner.verify(original: original, replacement: replacement,
                                                 observedFullText: "Intro. The pilot may reduce errors. Outro. Outro.", observedRangeText: nil), .unexpected)
        XCTAssertEqual(ReplacementPlanner.verify(original: original, replacement: replacement,
                                                 observedFullText: nil, observedRangeText: nil), .unverifiable)
        var noFull = original
        noFull.fullText = nil
        XCTAssertEqual(ReplacementPlanner.verify(original: noFull, replacement: replacement,
                                                 observedFullText: nil, observedRangeText: replacement), .confirmed)
    }
}

final class ClipboardTransactionTests: XCTestCase {
    final class FakePasteboard: PasteboardAccess {
        var changeCount = 10
        var items: [PasteboardItemSnapshot] = [PasteboardItemSnapshot(dataByType: ["public.rtf": Data("{\\rtf1 hi}".utf8),
                                                                                   "public.utf8-plain-text": Data("hi".utf8)])]
        func snapshotItems() -> [PasteboardItemSnapshot] { items }
        func writePlainText(_ text: String) -> Int {
            changeCount += 1
            items = [PasteboardItemSnapshot(dataByType: ["public.utf8-plain-text": Data(text.utf8)])]
            return changeCount
        }
        func restore(_ saved: [PasteboardItemSnapshot]) -> Int { changeCount += 1; items = saved; return changeCount }
        func userCopies(_ s: String) { _ = writePlainText(s) }
    }

    /// A32: restore only while Anti-slop still owns the clipboard change.
    func testRestoresPriorContentWhenStillOwned() {
        let pb = FakePasteboard()
        let original = pb.items
        let t = ClipboardTransaction(pasteboard: pb)
        t.writeReplacement("replacement")
        XCTAssertEqual(t.finish(), .restored)
        XCTAssertEqual(pb.items, original)
    }

    func testNeverOverwritesNewerUserCopy() {
        let pb = FakePasteboard()
        let t = ClipboardTransaction(pasteboard: pb)
        t.writeReplacement("replacement")
        pb.userCopies("user copied this meanwhile")
        XCTAssertEqual(t.finish(), .skippedNewerContent)
        XCTAssertEqual(pb.items.first?.dataByType["public.utf8-plain-text"], Data("user copied this meanwhile".utf8))
    }
}

final class PanelPlacementTests: XCTestCase {
    let screen = PanelRect(x: 0, y: 0, width: 1440, height: 875)
    let size = (width: 430.0, height: 320.0)

    func testPrefersRightWithRoom() {
        let sel = PanelRect(x: 100, y: 500, width: 500, height: 60)
        let r = PanelPlacement.place(size: size, selection: sel, visibleFrames: [screen], fallbackPoint: (0, 0))
        XCTAssertEqual(r.side, .right)
        XCTAssertEqual(r.frame.x, 612)
        XCTAssertEqual(r.frame.maxY, sel.maxY, "top-aligned with the selection")
    }

    func testFallsBackLeftBelowAbove() {
        let nearRight = PanelRect(x: 1100, y: 500, width: 300, height: 40)
        XCTAssertEqual(PanelPlacement.place(size: size, selection: nearRight, visibleFrames: [screen], fallbackPoint: (0, 0)).side, .left)
        let wide = PanelRect(x: 20, y: 600, width: 1400, height: 40)
        XCTAssertEqual(PanelPlacement.place(size: size, selection: wide, visibleFrames: [screen], fallbackPoint: (0, 0)).side, .below)
        let wideLow = PanelRect(x: 20, y: 60, width: 1400, height: 40)
        XCTAssertEqual(PanelPlacement.place(size: size, selection: wideLow, visibleFrames: [screen], fallbackPoint: (0, 0)).side, .above)
    }

    /// A35: always inside the visible frame, even when nothing fits.
    func testClampsAndMinimizesOverlapWhenNothingFits() {
        let huge = PanelRect(x: 10, y: 10, width: 1420, height: 855)
        let r = PanelPlacement.place(size: size, selection: huge, visibleFrames: [screen], fallbackPoint: (0, 0))
        XCTAssertEqual(r.side, .overlapping)
        XCTAssertTrue(screen.contains(r.frame))
    }

    func testSecondDisplayAndUnanchoredFallback() {
        let second = PanelRect(x: 1440, y: -200, width: 1920, height: 1055)
        let sel = PanelRect(x: 2000, y: 300, width: 200, height: 30)
        let r = PanelPlacement.place(size: size, selection: sel, visibleFrames: [screen, second], fallbackPoint: (0, 0))
        XCTAssertTrue(second.contains(r.frame))
        let u = PanelPlacement.place(size: size, selection: nil, visibleFrames: [screen, second], fallbackPoint: (1430, 20))
        XCTAssertEqual(u.side, .unanchored)
        XCTAssertTrue(screen.contains(u.frame))
    }
}

final class ShortcutAdvisorTests: XCTestCase {
    func b(_ code: Int, _ mods: [ShortcutModifier], _ char: String? = nil) -> ShortcutBinding {
        ShortcutBinding(keyCode: code, displayLabel: KeyCodes.label(keyCode: code, character: char, modifiers: mods), modifiers: mods)
    }

    /// A03: an ordinary single key is allowed, with its consumption explained.
    func testSingleOrdinaryKeyIsAllowedWithWarning() {
        let a = ShortcutAdvisor.assess(b(0x07, [], "x"), systemHotKeys: [])
        XCTAssertTrue(a.isUsable)
        XCTAssertTrue(a.warnings.first?.contains("X will trigger Anti-slop instead of typing") ?? false)
        let f = ShortcutAdvisor.assess(b(0x60, []), systemHotKeys: [])
        XCTAssertTrue(f.isUsable)
        XCTAssertTrue(f.warnings.first?.contains("F5") ?? false)
    }

    func testCombinationWithoutKnownConflictHasNoWarnings() {
        let a = ShortcutAdvisor.assess(b(0x03, [.control, .option], "f"), systemHotKeys: [])
        XCTAssertEqual(a, ShortcutAssessment(blocking: nil, warnings: []))
        XCTAssertEqual(b(0x03, [.command, .control, .option, .shift], "f").displayLabel, "⌃⌥⇧⌘F")
    }

    /// A05: real restrictions and known conflicts are explained, never remapped.
    func testRestrictionsAndConflicts() {
        XCTAssertNotNil(ShortcutAdvisor.assess(b(0x38, []), systemHotKeys: []).blocking)
        XCTAssertNotNil(ShortcutAdvisor.assess(b(0x30, [.command]), systemHotKeys: []).blocking)
        XCTAssertNotNil(ShortcutAdvisor.assess(b(0x00, [.function], "a"), systemHotKeys: []).blocking)
        let spotlight = SystemHotKey(id: 64, keyCode: 0x31, modifiers: [.command])
        let s = ShortcutAdvisor.assess(b(0x31, [.command]), systemHotKeys: [spotlight])
        XCTAssertTrue(s.blocking?.contains("Spotlight") ?? false)
        let copy = ShortcutAdvisor.assess(b(0x08, [.command], "c"), systemHotKeys: [])
        XCTAssertTrue(copy.isUsable)
        XCTAssertTrue(copy.warnings.contains { $0.contains("Copy") })
    }

    func testSymbolicHotKeyMaskParsing() {
        XCTAssertEqual(SystemHotKey.modifiers(fromMask: 1_048_576), [.command])
        XCTAssertEqual(SystemHotKey.modifiers(fromMask: 1_179_648), [.command, .shift])
        XCTAssertEqual(SystemHotKey.modifiers(fromMask: 262_144), [.control])
    }
}
