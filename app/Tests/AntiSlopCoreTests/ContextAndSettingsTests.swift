import XCTest
@testable import AntiSlopCore

final class ContextBuilderTests: XCTestCase {
    func range(_ full: String, _ sel: String) -> TextRange {
        let ns = full as NSString
        let r = ns.range(of: sel)
        return TextRange(location: r.location, length: r.length)
    }

    /// A14 / fixture partial_whitespace: exact selection and grammatical join.
    func testPartialSelectionKeepsBoundaryWhitespaceAndJoin() throws {
        let full = "The change may reduce errors."
        let r = TextRange(location: 10, length: 12) // " may reduce "
        let c = try ContextBuilder.build(selectedText: " may reduce ", fullText: full, selectedRange: r,
                                         fullTextIsComplete: true, sourceHint: .none).get()
        XCTAssertEqual(c.selectedText, " may reduce ")
        XCTAssertEqual(c.context.before, .excerpt("The change"))
        XCTAssertEqual(c.context.after, .excerpt("errors."))
    }

    /// A13: a confirmed document edge differs from an unavailable one.
    func testDocumentBoundaryOnlyWhenValueIsComplete() throws {
        let full = "Whole text."
        let r = TextRange(location: 0, length: 11)
        let complete = try ContextBuilder.build(selectedText: full, fullText: full, selectedRange: r,
                                                fullTextIsComplete: true, sourceHint: .none).get()
        XCTAssertEqual(complete.context.before, .documentBoundary)
        XCTAssertEqual(complete.context.after, .documentBoundary)
        let partial = try ContextBuilder.build(selectedText: full, fullText: full, selectedRange: r,
                                               fullTextIsComplete: false, sourceHint: .none).get()
        XCTAssertEqual(partial.context.before, .unavailable)
        XCTAssertEqual(partial.context.after, .unavailable)
        let none = try ContextBuilder.build(selectedText: full, fullText: nil, selectedRange: nil,
                                            fullTextIsComplete: false, sourceHint: .none).get()
        XCTAssertEqual(none.context, .unavailable)
    }

    func testMismatchedRangeFallsBackToSelectionOnly() throws {
        let c = try ContextBuilder.build(selectedText: "alpha", fullText: "beta alpha gamma",
                                         selectedRange: TextRange(location: 0, length: 5),
                                         fullTextIsComplete: true, sourceHint: .none).get()
        XCTAssertEqual(c.context, .unavailable)
        XCTAssertEqual(c.selectedText, "alpha")
    }

    func testExcerptsAreBoundedAndCutOnlyAtTheFarEnd() throws {
        let para = "Opening paragraph that is long enough to need cutting.\n"
        let before = String(repeating: "word ", count: 500) + para + "The joined phrase ends right here"
        let after = " and continues here. " + String(repeating: "more text ", count: 400)
        let sel = " SELECTED "
        let full = before + sel + after
        let c = try ContextBuilder.build(selectedText: sel, fullText: full, selectedRange: range(full, sel),
                                         fullTextIsComplete: true, sourceHint: .none).get()
        let b = try XCTUnwrap(c.context.before.text), a = try XCTUnwrap(c.context.after.text)
        XCTAssertLessThanOrEqual(b.codePointCount, Limits.contextPerSide)
        XCTAssertLessThanOrEqual(a.codePointCount, Limits.contextPerSide)
        XCTAssertTrue(b.hasSuffix("The joined phrase ends right here"), "text adjacent to the selection is exact")
        XCTAssertTrue(a.hasPrefix(" and continues here."))
        XCTAssertFalse(b.hasPrefix("ord"), "far cut lands on a boundary")
        XCTAssertTrue(before.hasSuffix(b) && after.hasPrefix(a))
    }

    /// A11: no selection / oversized are refused locally, never truncated.
    func testRefusals() {
        XCTAssertEqual(ContextBuilder.build(selectedText: "", fullText: nil, selectedRange: nil, fullTextIsComplete: false, sourceHint: .none),
                       .failure(.noSelection))
        XCTAssertEqual(ContextBuilder.build(selectedText: " \n\t", fullText: nil, selectedRange: nil, fullTextIsComplete: false, sourceHint: .none),
                       .failure(.noSelection))
        let big = String(repeating: "b", count: Limits.selectedText + 5)
        XCTAssertEqual(ContextBuilder.build(selectedText: big, fullText: nil, selectedRange: nil, fullTextIsComplete: false, sourceHint: .none),
                       .failure(.tooLong(count: Limits.selectedText + 5)))
        XCTAssertEqual(CaptureRefusal.tooLong(count: 25_000).message,
                       "That selection is 25,000 characters. Select less than 20,000 characters.")
    }

    func testSplitRejectsRangesInsideSurrogatePairs() {
        let s = "a🚀b" // rocket is two UTF-16 units
        XCTAssertNil(ContextBuilder.split(s, at: TextRange(location: 2, length: 1)))
        XCTAssertEqual(ContextBuilder.split(s, at: TextRange(location: 1, length: 2))?.selection, "🚀")
        XCTAssertNil(ContextBuilder.split(s, at: TextRange(location: 3, length: 5)))
    }

    func testTentativeClassification() {
        XCTAssertEqual(ContextBuilder.classify("if (isEnabled && !isExpired) { sendAlert(); }"), .code)
        XCTAssertEqual(ContextBuilder.classify("Only enabled accounts can receive alerts."), .prose)
        XCTAssertEqual(ContextBuilder.classify("Call the helper like this:\nlet x = compute(a, b);"), .mixed)
        XCTAssertEqual(ContextBuilder.classify("42"), .unknown)
    }
}

final class SettingsTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A07: every preference survives save and reload.
    func testSaveAndReloadPreservesEverything() throws {
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
        XCTAssertEqual(store.load(), .firstLaunch)
        let s = AppSettings(
            providerID: .codex,
            shortcut: ShortcutBinding(keyCode: 0x03, displayLabel: "⌃⌥F", modifiers: [.option, .control]),
            styleProfileID: .humanizer,
            writingPreferences: WritingPreferences(simplifyWording: true, keepMyTone: false, avoidEmDashes: true),
            customWriterInstructions: "Keep it direct.\nNo exclamation marks.",
            styleGuide: StyleGuide(label: "Firm style", text: "Use “Agreement” for the defined term.")
        )
        try store.save(s)
        XCTAssertEqual(SettingsStore(fileURL: store.fileURL).load(), .loaded(s))
        XCTAssertEqual(try SchemaCheck.validate(s, against: "schemas/settings.schema.json"), [])
        XCTAssertEqual(s.shortcut?.modifiers, [.control, .option], "normalized display order")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(leftovers, ["settings.json"], "atomic write leaves no temp files")
    }

    func testUnreadableSettingsArePreservedNotDeleted() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"schema_version":"0.1","custom_writer_instructions":"precious"}"#.utf8).write(to: url)
        guard case .unreadable(let preserved) = SettingsStore(fileURL: url).load() else { return XCTFail("expected unreadable") }
        XCTAssertTrue(try String(contentsOfFile: preserved, encoding: .utf8).contains("precious"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDefaultsMatchUX() {
        let s = AppSettings.firstLaunch(provider: .claudeCode)
        XCTAssertEqual(s.styleProfileID, .noAISlop)
        XCTAssertFalse(s.writingPreferences.simplifyWording)
        XCTAssertTrue(s.writingPreferences.keepMyTone)
        XCTAssertFalse(s.writingPreferences.avoidEmDashes)
        XCTAssertNil(s.shortcut)
        XCTAssertEqual(AppSettings.firstLaunchProvider(ready: [.codex]), .codex)
        XCTAssertEqual(AppSettings.firstLaunchProvider(ready: [.claudeCode]), .claudeCode)
        XCTAssertEqual(AppSettings.firstLaunchProvider(ready: [.codex, .claudeCode]), .claudeCode)
        XCTAssertEqual(AppSettings.firstLaunchProvider(ready: []), .claudeCode)
    }

    func testValidatorFlagsLimitsWithoutTruncating() {
        var s = AppSettings(providerID: .claudeCode)
        s.customWriterInstructions = String(repeating: "x", count: Limits.customInstructions + 1)
        s.styleGuide = StyleGuide(label: "", text: " ")
        let issues = SettingsValidator.issues(in: s)
        XCTAssertTrue(issues.contains(.customInstructionsTooLong(count: Limits.customInstructions + 1)))
        XCTAssertTrue(issues.contains(.guideLabelMissing))
        XCTAssertTrue(issues.contains(.guideTextMissing))
        XCTAssertEqual(s.customWriterInstructions.count, Limits.customInstructions + 1)
        XCTAssertEqual(SettingsValidator.issues(in: AppSettings(providerID: .codex)), [])
    }
}
