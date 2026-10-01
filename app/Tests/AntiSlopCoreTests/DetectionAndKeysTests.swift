import XCTest
@testable import AntiSlopCore

final class DetectionValidatorTests: XCTestCase {
    let source = "It is worth noting that the pilot may reduce errors. In today's fast-paced world, speed matters."

    func testValidFindingsAreKeptInOrder() throws {
        let json = #"{"summary":"Two filler openers","findings":[{"quote":"It is worth noting that","issue":"Empty lead-in."},{"quote":"In today's fast-paced world,","issue":"Stock stage-setting."}]}"#
        let r = try DetectionValidator.validate(jsonText: json, originalSelection: source).get()
        XCTAssertEqual(r.summary, "Two filler openers")
        XCTAssertEqual(r.findings.map(\.quote), ["It is worth noting that", "In today's fast-paced world,"])
        XCTAssertEqual(r.droppedFindings, 0)
    }

    /// The panel only ever quotes text the writer selected.
    func testQuotesNotInTheSelectionAreDropped() throws {
        let json = #"{"summary":"One issue","findings":[{"quote":"It is worth noting","issue":"Lead-in."},{"quote":"a paraphrase that is not there","issue":"Made up."},{"quote":"  ","issue":"Blank."}]}"#
        let r = try DetectionValidator.validate(jsonText: json, originalSelection: source).get()
        XCTAssertEqual(r.findings.count, 1)
        XCTAssertEqual(r.droppedFindings, 2)
    }

    func testEmptyFindingsAreValid() throws {
        let r = try DetectionValidator.validate(jsonText: #"{"summary":"Reads cleanly","findings":[]}"#, originalSelection: source).get()
        XCTAssertTrue(r.findings.isEmpty)
    }

    func testShapeViolationsAreRejected() {
        func check(_ json: String, _ expected: ResponseValidationError) {
            guard case .failure(let e) = DetectionValidator.validate(jsonText: json, originalSelection: source) else {
                return XCTFail("accepted \(json)")
            }
            XCTAssertEqual(e, expected)
        }
        check(#"{"summary":"x","findings":[],"score":0.9}"#, .unexpectedProperty("score"))
        check(#"{"summary":"x"}"#, .missingProperty("findings"))
        check(#"{"summary":" ","findings":[]}"#, .empty("summary"))
        check(#"{"summary":"x","findings":[{"quote":"pilot","issue":"y","severity":1}]}"#, .unexpectedProperty("finding.severity"))
        check(#"{"summary":"x","findings":"none"}"#, .wrongType("findings"))
        let many = (0..<13).map { _ in #"{"quote":"pilot","issue":"y"}"# }.joined(separator: ",")
        check(#"{"summary":"x","findings":[\#(many)]}"#, .tooLong("findings"))
        check("Here you go: {}", .notSingleObject)
    }

    func testDetectionUsesItsOwnInstructionsWithTheProfile() throws {
        let settings = AppSettings(providerID: .claudeCode)
        let detect = try PromptComposer.compose(capture: capture(source), settings: settings, mode: .detect)
        XCTAssertEqual(detect.mode, .detect)
        XCTAssertTrue(detect.instructions.hasPrefix(PromptLibrary.bundled.detectionInstructions))
        XCTAssertFalse(detect.instructions.contains("reviewed_profile_rules"))
        XCTAssertFalse(detect.instructions.contains(PromptLibrary.bundled.primaryInstructions))
        let rewrite = try PromptComposer.compose(capture: capture(source), settings: settings)
        XCTAssertEqual(rewrite.mode, .rewrite)
        XCTAssertTrue(rewrite.instructions.hasPrefix(PromptLibrary.bundled.primaryInstructions))
        XCTAssertEqual(detect.dataMessage.contains(source), rewrite.dataMessage.contains(source))
    }

    func testDetectionPromptNeverAsksForAScore() {
        let body = PromptLibrary.bundled.detectionInstructions
        XCTAssertTrue(body.contains("do not infer, estimate or score whether a person or AI wrote it"))
        XCTAssertTrue(body.contains("shall, must and may"))
    }
}

@MainActor
final class DetectionCoordinatorTests: XCTestCase {
    let text = "It is worth noting that the pilot may reduce errors."

    func make(_ provider: FixtureProvider, replacer: StubReplacer = StubReplacer()) -> (SessionCoordinator, StubCapturer) {
        let cap = StubCapturer(.success(snapshot(text)))
        let c = SessionCoordinator(capturer: cap, replacer: replacer, settings: { AppSettings(providerID: .claudeCode) },
                                   provider: { _ in provider }, timeout: 5)
        return (c, cap)
    }

    func waitFor(_ c: SessionCoordinator, _ predicate: @escaping (RewriteSession) -> Bool) async {
        for _ in 0..<200 {
            if let s = c.session, predicate(s) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out; phase=\(String(describing: c.session?.phase))")
    }

    func testDetectionShowsFindingsAndNeverApplies() async {
        let rep = StubReplacer()
        let (c, _) = make(FixtureProvider(delay: 0.01), replacer: rep)
        XCTAssertEqual(c.trigger(mode: .detect), .started)
        XCTAssertEqual(c.session?.mode, .detect)
        await waitFor(c) { $0.phase == .ready }
        XCTAssertEqual(c.session?.detection?.findings.map(\.quote), ["It is worth noting that"])
        XCTAssertEqual(c.session?.applyAvailability, .disabled(reason: nil))
        c.edit("anything")
        await c.apply()
        XCTAssertTrue(rep.writes.isEmpty, "detection can never write to the source")
    }

    /// The anti-slop key over a slop check rewrites the same captured selection
    /// without capturing again, then applies through the normal checks.
    func testSwitchToRewriteKeepsTheOriginalCapture() async {
        let rep = StubReplacer()
        let (c, cap) = make(FixtureProvider(delay: 0.01), replacer: rep)
        _ = c.trigger(mode: .detect)
        await waitFor(c) { $0.phase == .ready }
        let checked = c.session
        XCTAssertTrue(c.switchToRewrite())
        XCTAssertEqual(checked?.phase, .cancelled)
        XCTAssertEqual(c.session?.mode, .rewrite)
        XCTAssertEqual(cap.calls, 1)
        await waitFor(c) { $0.phase == .ready }
        XCTAssertEqual(c.session?.draft, "The pilot may reduce errors.")
        await c.apply()
        XCTAssertEqual(rep.writes, ["The pilot may reduce errors."])
        XCTAssertFalse(c.switchToRewrite(), "only a detection session converts")
    }

    func testSwitchDuringCheckCancelsIt() async {
        let (c, _) = make(FixtureProvider(behavior: .hang))
        _ = c.trigger(mode: .detect)
        XCTAssertEqual(c.trigger(mode: .rewrite), .focusExisting, "the coordinator never starts a second capture")
        XCTAssertTrue(c.switchToRewrite())
        XCTAssertEqual(c.session?.mode, .rewrite)
        XCTAssertEqual(c.session?.phase, .generating)
        c.cancel()
    }

    func testDetectionFailureOffersRetry() async {
        let fixture = FixtureProvider(behavior: .fail(.offline(.claudeCode)), delay: 0.01)
        let (c, _) = make(fixture)
        _ = c.trigger(mode: .detect)
        await waitFor(c) { if case .failed = $0.phase { return true }; return false }
        fixture.behavior = .lightEdit
        c.retry()
        await waitFor(c) { $0.phase == .ready }
        XCTAssertEqual(c.session?.mode, .detect)
        XCTAssertNotNil(c.session?.detection)
    }
}

final class DetectShortcutSettingsTests: XCTestCase {
    func testDetectShortcutRoundTripsAndOldFilesStillLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
        let s = AppSettings(providerID: .codex,
                            shortcut: ShortcutBinding(keyCode: 0x3D, displayLabel: "Right ⌥", modifiers: []),
                            detectShortcut: ShortcutBinding(keyCode: 0x60, displayLabel: "F5", modifiers: []))
        try store.save(s)
        XCTAssertEqual(store.load(), .loaded(s))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL))
        XCTAssertEqual(try SchemaCheck.validate(s, against: "schemas/settings.schema.json"), [])

        // Settings saved before slop-detection mode have no detect_shortcut key.
        var old = try XCTUnwrap(json as? [String: Any])
        old.removeValue(forKey: "detect_shortcut")
        try JSONSerialization.data(withJSONObject: old).write(to: store.fileURL)
        guard case .loaded(let loaded) = store.load() else { return XCTFail("old settings no longer load") }
        XCTAssertNil(loaded.detectShortcut)
        XCTAssertEqual(loaded.shortcut, s.shortcut)
    }

    func testTheTwoKeysMustDiffer() {
        let k = ShortcutBinding(keyCode: 0x32, displayLabel: "`", modifiers: [])
        let s = AppSettings(providerID: .claudeCode, shortcut: k,
                            detectShortcut: ShortcutBinding(keyCode: 0x32, displayLabel: "` (again)", modifiers: []))
        XCTAssertEqual(SettingsValidator.issues(in: s), [.shortcutsCollide])
    }
}

final class LoneModifierTests: XCTestCase {
    // Raw NSEvent.ModifierFlags bits used below.
    let option: UInt = 0x80000, rightOption: UInt = 0x40, leftOption: UInt = 0x20
    let command: UInt = 0x100000, leftCommand: UInt = 0x8, fn: UInt = 0x800000, capsState: UInt = 0x10000

    func b(_ code: Int) -> ShortcutBinding {
        ShortcutBinding(keyCode: code, displayLabel: KeyCodes.label(keyCode: code, character: nil, modifiers: []), modifiers: [])
    }

    func testAnyModifierKeyAloneIsAssignableWithHonestWarnings() {
        for code in KeyCodes.modifierOnly {
            let a = ShortcutAdvisor.assess(b(code), systemHotKeys: [])
            XCTAssertNil(a.blocking, "key \(code)")
            XCTAssertTrue(a.warnings.contains { $0.contains("Accessibility") })
        }
        XCTAssertEqual(b(0x3D).displayLabel, "Right ⌥")
        XCTAssertEqual(b(0x3F).displayLabel, "Fn")
        XCTAssertEqual(b(0x39).displayLabel, "Caps Lock")
        XCTAssertTrue(b(0x3D).isLoneModifier)
        XCTAssertTrue(ShortcutAdvisor.assess(b(0x38), systemHotKeys: []).warnings.contains { $0.contains("by accident") })
    }

    func testPlainKeyWarnsThatItAppliesInThePanel() {
        let grave = ShortcutBinding(keyCode: 0x32, displayLabel: "`", modifiers: [])
        XCTAssertTrue(ShortcutAdvisor.assess(grave, systemHotKeys: [], appliesInPanel: true).warnings.contains { $0.contains("applies the rewrite") })
        XCTAssertFalse(ShortcutAdvisor.assess(grave, systemHotKeys: []).warnings.contains { $0.contains("applies the rewrite") })
    }

    func testPressAndReleaseAloneFires() {
        var d = LoneModifierDetector(keyCode: 0x3D)
        let t = Date()
        XCTAssertFalse(d.flagsChanged(keyCode: 0x3D, flags: option | rightOption, at: t))
        XCTAssertTrue(d.flagsChanged(keyCode: 0x3D, flags: 0, at: t.addingTimeInterval(0.2)))
        XCTAssertFalse(d.flagsChanged(keyCode: 0x3D, flags: 0, at: t.addingTimeInterval(0.3)), "one release, one trigger")
    }

    func testCombinationsAndLongHoldsDoNotFire() {
        let t = Date()
        var d = LoneModifierDetector(keyCode: 0x3D)
        _ = d.flagsChanged(keyCode: 0x3D, flags: option | rightOption, at: t)
        d.otherKeyDown() // ⌥ + a letter
        XCTAssertFalse(d.flagsChanged(keyCode: 0x3D, flags: 0, at: t.addingTimeInterval(0.2)))

        _ = d.flagsChanged(keyCode: 0x3D, flags: option | rightOption, at: t)
        XCTAssertFalse(d.flagsChanged(keyCode: 0x3D, flags: 0, at: t.addingTimeInterval(1.5)), "held too long")

        // ⌘ already down, then Right ⌥ tapped: a chord, not a lone press.
        _ = d.flagsChanged(keyCode: 0x3D, flags: command | leftCommand | option | rightOption, at: t)
        XCTAssertFalse(d.flagsChanged(keyCode: 0x3D, flags: command | leftCommand, at: t.addingTimeInterval(0.1)))

        // Right ⌥ down, then ⌘ pressed and released before ⌥ is released.
        _ = d.flagsChanged(keyCode: 0x3D, flags: option | rightOption, at: t)
        _ = d.flagsChanged(keyCode: 0x37, flags: option | rightOption | command | leftCommand, at: t)
        XCTAssertFalse(d.flagsChanged(keyCode: 0x3D, flags: 0, at: t.addingTimeInterval(0.2)))
    }

    func testLeftAndRightAreDistinct() {
        let t = Date()
        var right = LoneModifierDetector(keyCode: 0x3D)
        XCTAssertFalse(right.flagsChanged(keyCode: 0x3A, flags: option | leftOption, at: t))
        XCTAssertFalse(right.flagsChanged(keyCode: 0x3A, flags: 0, at: t.addingTimeInterval(0.1)), "Left ⌥ is not Right ⌥")
        // Both options down: releasing Right ⌥ while Left is held is not a lone press.
        XCTAssertFalse(right.flagsChanged(keyCode: 0x3D, flags: option | leftOption | rightOption, at: t))
        XCTAssertFalse(right.flagsChanged(keyCode: 0x3D, flags: option | leftOption, at: t.addingTimeInterval(0.1)))
    }

    func testFnAndCapsLock() {
        let t = Date()
        var f = LoneModifierDetector(keyCode: KeyCodes.fn)
        XCTAssertFalse(f.flagsChanged(keyCode: KeyCodes.fn, flags: fn, at: t))
        XCTAssertTrue(f.flagsChanged(keyCode: KeyCodes.fn, flags: 0, at: t.addingTimeInterval(0.1)))

        var c = LoneModifierDetector(keyCode: KeyCodes.capsLock)
        XCTAssertTrue(c.flagsChanged(keyCode: KeyCodes.capsLock, flags: capsState, at: t), "each Caps Lock change is a press")
        XCTAssertFalse(c.flagsChanged(keyCode: KeyCodes.capsLock, flags: 0, at: t.addingTimeInterval(0.1)), "debounced")
        XCTAssertTrue(c.flagsChanged(keyCode: KeyCodes.capsLock, flags: 0, at: t.addingTimeInterval(1)))
    }
}

@MainActor
final class RequestTraceTests: XCTestCase {
    func testCoordinatorTracesOnlyWhenAsked() async throws {
        let fixture = FixtureProvider(delay: 0.01)
        let c = SessionCoordinator(capturer: StubCapturer(.success(snapshot("It is worth noting that the pilot may help."))),
                                   replacer: StubReplacer(), settings: { AppSettings(providerID: .claudeCode) },
                                   provider: { _ in fixture }, timeout: 5)
        _ = c.trigger()
        for _ in 0..<200 where c.session?.phase != .ready { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(fixture.requests.last?.trace, "no trace without the debug flag")
        c.clear()

        var traces: [RequestTrace] = []
        c.onTrace = { traces.append($0) }
        _ = c.trigger(mode: .detect)
        for _ in 0..<200 where traces.first?.snapshot.outcome == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        let s = try XCTUnwrap(traces.first?.snapshot)
        XCTAssertEqual(s.mode, .detect)
        XCTAssertEqual(s.instructions, fixture.requests.last?.instructions)
        XCTAssertTrue(s.dataMessage.contains("It is worth noting that the pilot may help."))
        XCTAssertEqual(s.schema, DetectionValidator.providerWireSchema)
        XCTAssertTrue(s.rawResponse?.contains("\"findings\"") ?? false)
        XCTAssertEqual(s.outcome, "Accepted")
    }
}

extension ProviderAdapterTests {
    func testClaudeTraceRecordsFullExchangeWithInstructionsElidedFromCommand() async throws {
        let (p, _) = try claude("ok")
        var c = try composed()
        let trace = RequestTrace(mode: .rewrite, provider: "Claude Code", instructions: c.instructions, dataMessage: c.dataMessage)
        c.trace = trace
        _ = try await p.rewrite(c, timeout: 10)
        let s = trace.snapshot
        XCTAssertTrue(s.command.contains("<instructions>"))
        XCTAssertFalse(s.command.contains(c.instructions))
        XCTAssertTrue(s.rawResponse?.contains("The pilot may reduce review time") ?? false)
        XCTAssertTrue(s.transcript?.contains("\"type\":\"result\"") ?? false)
        XCTAssertEqual(s.schema, ResponseValidator.providerWireSchema)
    }
}

final class ModelSelectionTests: XCTestCase {
    func testIdentifiersNeverLookLikeFlags() {
        for ok in ["sonnet", "gpt-6.1-sol", "claude-opus-5[1m]", "claude-fable-5-1"] { XCTAssertTrue(ModelIdentifier.isValidModel(ok), ok) }
        for bad in ["", "-m", "--model=x", "a b", "x;rm"] { XCTAssertFalse(ModelIdentifier.isValidModel(bad), bad) }
        XCTAssertTrue(ModelIdentifier.isValidLevel("xhigh"))
        XCTAssertFalse(ModelIdentifier.isValidLevel("--high"))
        XCTAssertFalse(ModelIdentifier.isValidLevel("High Effort"))
    }

    func testPreferencesPersistPerProviderAndReachTheRequest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
        var s = AppSettings(providerID: .codex)
        s.modelPreferences = [.codex: ModelPreference(model: "gpt-6.1-sol", reasoning: "high"),
                              .claudeCode: ModelPreference(model: "sonnet", reasoning: nil)]
        try store.save(s)
        XCTAssertEqual(store.load(), .loaded(s))
        XCTAssertEqual(try SchemaCheck.validate(s, against: "schemas/settings.schema.json"), [])

        let c = try PromptComposer.compose(capture: capture("Some text."), settings: s)
        XCTAssertEqual(c.model, "gpt-6.1-sol")
        XCTAssertEqual(c.reasoning, "high")
        XCTAssertFalse(c.dataMessage.contains("gpt-6.1-sol"), "the model choice is not model-visible data")

        s.providerID = .claudeCode
        let d = try PromptComposer.compose(capture: capture("Some text."), settings: s)
        XCTAssertEqual(d.model, "sonnet")
        XCTAssertNil(d.reasoning)
    }

    func testMalformedSavedChoiceFallsBackToRuntimeDefault() throws {
        var s = AppSettings(providerID: .claudeCode)
        s.modelPreferences[.claudeCode] = ModelPreference(model: "--dangerous", reasoning: "high")
        XCTAssertEqual(SettingsValidator.issues(in: s), [.modelChoiceInvalid])
        let c = try PromptComposer.compose(capture: capture("Some text."), settings: s)
        XCTAssertNil(c.model)
        XCTAssertNil(c.reasoning)
    }

    func testParsersKeepOnlyUsableListedModels() throws {
        let claude = """
        {"type":"system","subtype":"other"}
        {"type":"control_response","response":{"subtype":"success","request_id":"r","response":{"models":[{"value":"default","displayName":"Default","supportedEffortLevels":["low","max"]},{"value":"opus[1m]","displayName":"Opus","resolvedModel":"claude-opus-5[1m]","supportedEffortLevels":["low","NOT OK"]},{"value":"-x","displayName":"Bad"}]}}}
        """
        let models = try XCTUnwrap(ModelCatalogParser.claudeInitialize(stdout: claude, requestID: "r"))
        XCTAssertEqual(models.map(\.id), ["default", "opus[1m]"])
        XCTAssertTrue(models[0].isRuntimeDefault)
        XCTAssertEqual(models[1].reasoningLevels, ["low"])
        XCTAssertEqual(models[1].resolvedModel, "claude-opus-5[1m]")
        XCTAssertNil(ModelCatalogParser.claudeInitialize(stdout: claude, requestID: "other"))

        let codex = #"{"models":[{"slug":"b","priority":2,"visibility":"list"},{"slug":"a","priority":1,"visibility":"list","default_reasoning_level":"low","supported_reasoning_levels":[{"effort":"low"},{"effort":"max"},{"effort":"ultra"}]},{"slug":"h","visibility":"hide"}]}"#
        let cm = try XCTUnwrap(ModelCatalogParser.codexCatalog(Data(codex.utf8)))
        XCTAssertEqual(cm.map(\.id), ["a", "b"])
        XCTAssertEqual(cm[0].reasoningLevels, ["low", "max"], "delegating levels are not offered")
        XCTAssertEqual(cm[0].defaultReasoning, "low")
    }
}

extension ProviderAdapterTests {
    func withChoice(_ c: ComposedRequest, _ model: String?, _ reasoning: String?) -> ComposedRequest {
        var c = c
        c.model = model
        c.reasoning = reasoning
        return c
    }

    func testClaudeModelListAndChoiceFlags() async throws {
        let (p, fake) = try claude("ok")
        let models = try await p.availableModels()
        XCTAssertEqual(models.map(\.id), ["default", "sonnet", "haiku"], "a flag-like id is dropped")
        XCTAssertEqual(models[1].reasoningLevels, ["low", "medium", "high"])
        XCTAssertTrue(fake.argv.contains("--input-format"))
        XCTAssertEqual(fake.argv[fake.argv.firstIndex(of: "--tools")! + 1], "", "listing models enables no tools")

        _ = try await p.rewrite(withChoice(try composed(), "sonnet", "high"), timeout: 10)
        let argv = fake.argv
        XCTAssertEqual(argv[argv.firstIndex(of: "--model")! + 1], "sonnet")
        XCTAssertEqual(argv[argv.firstIndex(of: "--effort")! + 1], "high")

        _ = try await p.rewrite(try composed(), timeout: 10)
        XCTAssertFalse(fake.argv.contains("--model"), "runtime default sends no model flag")
        XCTAssertFalse(fake.argv.contains("--effort"))
    }

    func testCodexModelListAndChoiceFlags() async throws {
        let (p, fake) = try codex("ok")
        let models = try await p.availableModels()
        XCTAssertEqual(models.map(\.id), ["gpt-a", "gpt-b"], "hidden models are not offered; priority order")
        let r = try await p.rewrite(withChoice(try composed(), "gpt-b", "medium"), timeout: 10)
        let argv = fake.argv
        XCTAssertEqual(argv[argv.firstIndex(of: "--model")! + 1], "gpt-b")
        XCTAssertTrue(argv.contains(#"model_reasoning_effort="medium""#))
        XCTAssertEqual(r.receipt.model, "gpt-b")
    }

    func testTraceShowsRequestedAndReportedModel() async throws {
        let (p, _) = try claude("ok")
        var c = withChoice(try composed(), "sonnet", "low")
        let trace = RequestTrace(mode: .rewrite, provider: "Claude Code", instructions: c.instructions,
                                 dataMessage: c.dataMessage, model: c.model, reasoning: c.reasoning)
        c.trace = trace
        _ = try await p.rewrite(c, timeout: 10)
        XCTAssertEqual(trace.snapshot.requestedModel, "sonnet")
        XCTAssertEqual(trace.snapshot.requestedReasoning, "low")
        XCTAssertEqual(trace.snapshot.reportedModel, "fake-model")
    }
}
