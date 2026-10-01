#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import AntiSlopCore
@testable import AntiSlopMac

@MainActor
final class SettingsUITests: XCTestCase {
    let catalog = [ModelOption(id: "sonnet", displayName: "Sonnet", reasoningLevels: ["low", "medium", "high"]),
                   ModelOption(id: "opus[1m]", displayName: "Opus", reasoningLevels: ["high", "max"])]

    func testDoneResolvesVisibleIntelligenceAndKeepsComplexityIndependent() {
        let model = SettingsModel(settings: AppSettings(providerID: .claudeCode), isFirstLaunch: false, notice: nil)
        model.catalogs[.claudeCode] = .loaded(catalog)
        model.draft.writingPreferences.sentenceComplexity = .lawyer
        model.selectIntelligence(.genius, catalog: catalog)
        model.draft.launchAtLogin = false
        var saved: AppSettings?
        model.onDone = { saved = $0; return nil }
        model.done()
        XCTAssertEqual(saved?.modelPreference(for: .claudeCode), ModelPreference(model: "opus[1m]", reasoning: "max"))
        XCTAssertEqual(saved?.writingPreferences.sentenceComplexity, .lawyer)
        XCTAssertEqual(saved?.launchAtLogin, false)
    }

    func testFailedCatalogKeepsSavedModelAndDoneErrorKeepsSettingsOpen() {
        var settings = AppSettings(providerID: .codex)
        settings.modelPreferences[.codex] = ModelPreference(model: "saved-model", reasoning: "high")
        let model = SettingsModel(settings: settings, isFirstLaunch: false, notice: nil)
        model.catalogs[.codex] = .failed("Offline")
        var closed = false
        model.onClose = { closed = true }
        model.onDone = { new in
            XCTAssertEqual(new.modelPreference(for: .codex), settings.modelPreference(for: .codex))
            return "Startup needs macOS approval."
        }
        model.done()
        XCTAssertFalse(closed)
        XCTAssertEqual(model.errors, ["Startup needs macOS approval."])
    }

    func testNativeSliderKeepsTickSnappingAndNativeMovementCommands() {
        _ = NSApplication.shared
        var selected = 1
        let coordinator = NativeStepSlider.Coordinator(selection: Binding(get: { selected }, set: { selected = $0 }))
        coordinator.labels = Intelligence.allCases.map(\.displayName)
        let slider = NSSlider(frame: NSRect(x: 15, y: 15, width: 400, height: 30))
        slider.cell = BrandedSliderCell()
        slider.isVertical = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 60), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(slider)
        _ = window.makeFirstResponder(slider)
        defer { window.close() }
        slider.minValue = 0
        slider.maxValue = 3
        slider.numberOfTickMarks = 4
        slider.allowsTickMarkValuesOnly = true
        slider.isEnabled = true
        slider.isContinuous = true
        slider.target = coordinator
        slider.action = #selector(NativeStepSlider.Coordinator.changed(_:))
        slider.doubleValue = 1
        XCTAssertEqual(slider.closestTickMarkValue(toValue: 1.7), 2)
        // AppKit's movement commands (used by keyboard navigation) work without
        // requiring a visible key window or injecting hardware events into the desktop.
        slider.moveRight(nil)
        XCTAssertEqual(slider.doubleValue, 2)
        XCTAssertEqual(selected, 2)
        XCTAssertEqual(slider.accessibilityValueDescription(), "Smart")
        slider.moveLeft(nil)
        XCTAssertEqual(selected, 1)
        XCTAssertEqual(slider.accessibilityValueDescription(), "Average")
        _ = slider.accessibilityPerformIncrement()
        XCTAssertEqual(selected, 2)
        slider.doubleValue = 3
        coordinator.changed(slider)
        XCTAssertEqual(selected, 3)
        XCTAssertEqual(slider.accessibilityValueDescription(), "Genius")
    }

    func testMaximumSliderKeepsNativeThumbClearanceAndTrackAlignment() throws {
        _ = NSApplication.shared
        for width in [220.0, 400.0, 480.0] {
            for stops in [4, 5] {
                let frame = NSRect(x: 0, y: 0, width: width, height: 30)
                let slider = NSSlider(frame: frame)
                let native = NSSlider(frame: frame)
                slider.cell = BrandedSliderCell()
                for control in [slider, native] {
                    control.isVertical = false
                    control.minValue = 0
                    control.maxValue = Double(stops - 1)
                    control.numberOfTickMarks = stops
                    control.allowsTickMarkValuesOnly = true
                }
                let cell = try XCTUnwrap(slider.cell as? BrandedSliderCell)
                let nativeCell = try XCTUnwrap(native.cell as? NSSliderCell)
                cell.celebratesMaximum = true
                for value in 0..<stops {
                    slider.doubleValue = Double(value)
                    native.doubleValue = Double(value)
                    let knob = cell.knobRect(flipped: slider.isFlipped)
                    XCTAssertEqual(knob, nativeCell.knobRect(flipped: native.isFlipped))
                    XCTAssertTrue(slider.bounds.contains(knob), "The thumb must fit at both endpoints.")
                    let track = cell.maximumTrackRect(inside: cell.barRect(flipped: slider.isFlipped), flipped: slider.isFlipped)
                    XCTAssertEqual(track.midY, knob.midY, accuracy: 0.001)
                    XCTAssertEqual(cell.isCelebrating, value == stops - 1)
                }
                slider.isEnabled = false
                XCTAssertFalse(cell.isCelebrating)
                slider.isEnabled = true
                cell.celebratesMaximum = false
                XCTAssertFalse(cell.isCelebrating)
            }
        }
    }

    /// Inspect normal/max styling, native thumbs and card corners together.
    func testRenderSliderStates() async throws {
        guard let dir = ProcessInfo.processInfo.environment["ANTISLOP_UI_TEST_SHOTS"] else { return }
        _ = NSApplication.shared
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let view = VStack(spacing: 16) {
            StepSlider(title: "Intelligence", labels: Intelligence.allCases.map(\.displayName), selection: .constant(2), celebratesMaximum: true, bloomColor: Theme.action)
            StepSlider(title: "Sentence Complexity", labels: SentenceComplexity.allCases.map(\.displayName), selection: .constant(2), celebratesMaximum: true)
            StepSlider(title: "Intelligence", labels: Intelligence.allCases.map(\.displayName), selection: .constant(3), celebratesMaximum: true, bloomColor: Theme.action)
            StepSlider(title: "Sentence Complexity", labels: SentenceComplexity.allCases.map(\.displayName), selection: .constant(4), celebratesMaximum: true)
        }
        .padding(20)
        .background(Theme.shell)
        .preferredColorScheme(.light)
        try await render(view, size: NSSize(width: 540, height: 600), path: dir + "/slider-states.png")
    }

    /// Opt-in native-view render evidence; synthetic text only, no external apps or OS registration.
    func testRenderThreeScreens() async throws {
        guard let dir = ProcessInfo.processInfo.environment["ANTISLOP_UI_TEST_SHOTS"] else { return }
        _ = NSApplication.shared
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let settings = AppSettings(providerID: .claudeCode,
                                   shortcut: ShortcutBinding(keyCode: KeyCodes.home, displayLabel: "Home", modifiers: []),
                                   detectShortcut: ShortcutBinding(keyCode: KeyCodes.end, displayLabel: "End", modifiers: []))
        let model = SettingsModel(settings: settings, isFirstLaunch: false, notice: nil)
        model.draft.intelligence[.claudeCode] = .genius
        model.catalogs[.claudeCode] = .loaded(catalog)
        model.readiness[.claudeCode] = .fixtureOnly
        model.draft.writingPreferences.sentenceComplexity = .lawyer
        model.accessibilityTrusted = true
        try await render(SettingsView(model: model), size: NSSize(width: 540, height: 1130), path: dir + "/settings-lawyer.png")
        model.draft.writingPreferences.sentenceComplexity = .balanced
        model.draft.intelligence[.claudeCode] = .smart
        try await render(SettingsView(model: model), size: NSSize(width: 540, height: 820), path: dir + "/settings-balanced.png")
        try await render(SettingsView(model: model), size: NSSize(width: 540, height: 820), path: dir + "/settings-scrolled.png", scrollToBottom: true)
        let panel = PanelModel()
        panel.statusKind = .intent
        panel.statusText = "Looks like a qualified project update"
        panel.draft = "The pilot may reduce errors for some teams."
        panel.showsEditor = true
        panel.editorEditable = true
        panel.applyEnabled = true
        panel.isFixture = true
        try await render(PanelView(model: panel), size: NSSize(width: 430, height: 325), path: dir + "/rewrite.png")
        panel.mode = .detect
        panel.footerText = "⌘ Return to rewrite"
        panel.showsEditor = false
        panel.showsFindings = true
        panel.findingsHeight = 100
        panel.statusText = "One empty lead-in"
        panel.findings = try DetectionValidator.validate(jsonText: #"{"summary":"One empty lead-in","findings":[{"quote":"It is worth noting that","issue":"Empty lead-in delays the useful point."}]}"#, originalSelection: "It is worth noting that the pilot may reduce errors.").get().findings
        try await render(PanelView(model: panel), size: NSSize(width: 430, height: 285), path: dir + "/detection.png")
    }

    private func render<V: View>(_ view: V, size: NSSize, path: String, scrollToBottom: Bool = false) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.setContentSize(size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        if scrollToBottom {
            func findScrollView(in view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
            }
            let scroll = try XCTUnwrap(findScrollView(in: host))
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
            let bottom = document.isFlipped ? document.bounds.maxY - scroll.contentView.bounds.height : document.bounds.minY
            scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
#endif
