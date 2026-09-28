#if os(macOS)
import AntiSlopCore
import AppKit
import ApplicationServices

/// Thin, typed access to macOS accessibility attributes. Attribute names are
/// the documented string values (e.g. "AXSelectedText").
enum AX {
    static func trusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func copy(_ el: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, name as CFString, &value)
        return (err, value)
    }

    static func value(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        let (err, v) = copy(el, name)
        return err == .success ? v : nil
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        value(el, name) as? String
    }

    static func int(_ el: AXUIElement, _ name: String) -> Int? {
        (value(el, name) as? NSNumber)?.intValue
    }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func range(_ el: AXUIElement, _ name: String) -> CFRange? {
        guard let v = value(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        guard AXValueGetValue(v as! AXValue, .cfRange, &r) else { return nil }
        return r
    }

    static func isSettable(_ el: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(el, name as CFString, &settable) == .success && settable.boolValue
    }

    @discardableResult
    static func set(_ el: AXUIElement, _ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(el, name as CFString, value)
    }

    static func setRange(_ el: AXUIElement, _ name: String, _ r: CFRange) -> AXError {
        var range = r
        guard let v = AXValueCreate(.cfRange, &range) else { return .failure }
        return set(el, name, v)
    }

    static func parameterized(_ el: AXUIElement, _ name: String, _ param: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(el, name as CFString, param, &value)
        return err == .success ? value : nil
    }

    static func string(_ el: AXUIElement, for r: CFRange) -> String? {
        var range = r
        guard let p = AXValueCreate(.cfRange, &range) else { return nil }
        return parameterized(el, "AXStringForRange", p) as? String
    }

    /// Bounds in accessibility coordinates (top-left origin of the primary display).
    static func bounds(_ el: AXUIElement, for r: CFRange) -> CGRect? {
        var range = r
        guard let p = AXValueCreate(.cfRange, &range),
              let v = parameterized(el, "AXBoundsForRange", p), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(v as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    static func pid(_ el: AXUIElement) -> pid_t? {
        var p: pid_t = 0
        return AXUIElementGetPid(el, &p) == .success ? p : nil
    }

    static func focusedElement(ofApp pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        return element(app, "AXFocusedUIElement")
    }

    static func isSecure(_ el: AXUIElement) -> Bool {
        string(el, "AXSubrole") == "AXSecureTextField" || string(el, "AXRole") == "AXSecureTextField"
    }

    /// Convert an accessibility rectangle to global Cocoa coordinates (bottom-left origin).
    static func cocoaRect(fromAX r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

/// Opaque handle kept in the capture snapshot; never serialized or sent to a model.
final class TargetHandle {
    let element: AXUIElement
    let pid: pid_t
    init(element: AXUIElement, pid: pid_t) {
        self.element = element
        self.pid = pid
    }
}

/// Reads the exact selection and bounded context from the focused control of
/// the source application, before Anti-slop takes focus.
public final class AccessibilityCapture: SelectionCapturing {
    /// The most recent frontmost application that is not Anti-slop. Used when a
    /// capture is requested while Anti-slop's own panel is frontmost.
    public var lastExternalApp: () -> NSRunningApplication?

    public init(lastExternalApp: @escaping () -> NSRunningApplication? = { nil }) {
        self.lastExternalApp = lastExternalApp
    }

    public func captureFocusedSelection() -> Result<CaptureSnapshot, CaptureRefusal> {
        guard AX.trusted(prompt: false) else { return .failure(.accessibilityNotTrusted) }
        let me = ProcessInfo.processInfo.processIdentifier
        var app = NSWorkspace.shared.frontmostApplication
        if app?.processIdentifier == me { app = lastExternalApp() }
        guard let app, app.processIdentifier != me else { return .failure(.noSelection) }
        let pid = app.processIdentifier
        guard let el = AX.focusedElement(ofApp: pid) else { return .failure(.unreadable) }
        AXUIElementSetMessagingTimeout(el, 1.0)
        if AX.isSecure(el) { return .failure(.secureField) }

        let rangeCF = AX.range(el, "AXSelectedTextRange")
        let value = AX.string(el, "AXValue")
        var selected = AX.string(el, "AXSelectedText")
        let range = rangeCF.map { UTF16Range(location: $0.location, length: $0.length) }
        if selected == nil, let value, let range {
            selected = ContextBuilder.split(value, at: range)?.selection
        }
        guard let selected else {
            return .failure(rangeCF == nil && value == nil ? .notText : .unreadable)
        }
        if selected.isEmpty || (range?.length == 0) { return .failure(.noSelection) }

        let editable = AX.isSettable(el, "AXSelectedText") || AX.isSettable(el, "AXValue")
        guard editable else { return .failure(.notText) }

        let count = AX.int(el, "AXNumberOfCharacters")
        let complete = value != nil && (count == nil || count == value!.utf16.count)
        let hint = sourceHint(app: app, element: el)
        let captured: CapturedText
        switch ContextBuilder.build(selectedText: selected, fullText: value, selectedRange: range,
                                    fullTextIsComplete: complete, sourceHint: hint) {
        case .failure(let r): return .failure(r)
        case .success(let c): captured = c
        }

        var bounds: PanelRect? = nil
        if let rangeCF, let r = AX.bounds(el, for: rangeCF), r.width > 0 || r.height > 0 {
            let c = AX.cocoaRect(fromAX: r)
            bounds = PanelRect(x: c.minX, y: c.minY, width: max(c.width, 1), height: max(c.height, 1))
        }

        let keepFull = (value?.utf16.count ?? 0) <= Limits.retainedFullTextUTF16 ? value : nil
        let evidence = TargetEvidence(processID: pid, bundleID: app.bundleIdentifier, role: AX.string(el, "AXRole"),
                                      isSecure: false, isEditable: editable, selectedText: selected,
                                      selectedRange: range, fullText: keepFull)
        return .success(CaptureSnapshot(captured: captured, target: evidence, selectionBounds: bounds,
                                        handle: TargetHandle(element: el, pid: pid)))
    }

    func sourceHint(app: NSRunningApplication, element: AXUIElement) -> SourceHint {
        var title: String? = nil
        var typeHint: String? = nil
        if let window = AX.element(element, "AXWindow") {
            title = AX.string(window, "AXTitle")
            // The document URL only informs a type hint; the file itself is never opened.
            if let doc = AX.string(window, "AXDocument"), let url = URL(string: doc) {
                typeHint = Self.typeHint(forExtension: url.pathExtension.lowercased())
            }
        }
        return SourceHint(appName: app.localizedName, documentTitle: title?.isEmpty == true ? nil : title,
                          contentTypeHint: typeHint)
    }

    static func typeHint(forExtension ext: String) -> String? {
        switch ext {
        case "txt", "text": return "plain text document"
        case "md", "markdown": return "Markdown document"
        case "rtf", "rtfd": return "rich text document"
        case "doc", "docx": return "word-processing document"
        case "pages": return "Pages document"
        case "eml", "emlx": return "email"
        case "html", "htm": return "web page"
        case "tex": return "LaTeX document"
        case "": return nil
        default: return nil
        }
    }

    /// Observe the target now, for revalidation immediately before a write.
    static func observe(_ snap: CaptureSnapshot) -> TargetObservation {
        guard let handle = snap.handle as? TargetHandle else {
            return TargetObservation(appIsRunning: false, isSameElement: false, isFocusedInApp: false, evidence: nil)
        }
        let running = NSRunningApplication(processIdentifier: handle.pid).map { !$0.isTerminated } ?? false
        guard running else {
            return TargetObservation(appIsRunning: false, isSameElement: false, isFocusedInApp: false, evidence: nil)
        }
        let el = handle.element
        let (roleErr, _) = AX.copy(el, "AXRole")
        let alive = roleErr != .invalidUIElement && roleErr != .cannotComplete
        let focused = AX.focusedElement(ofApp: handle.pid).map { CFEqual($0, el) } ?? false
        guard alive else {
            return TargetObservation(appIsRunning: true, isSameElement: false, isFocusedInApp: false, evidence: nil)
        }
        let range = AX.range(el, "AXSelectedTextRange").map { UTF16Range(location: $0.location, length: $0.length) }
        let value = AX.string(el, "AXValue")
        let evidence = TargetEvidence(
            processID: handle.pid,
            bundleID: snap.target.bundleID,
            role: AX.string(el, "AXRole"),
            isSecure: AX.isSecure(el),
            isEditable: AX.isSettable(el, "AXSelectedText") || AX.isSettable(el, "AXValue"),
            selectedText: AX.string(el, "AXSelectedText"),
            selectedRange: range,
            fullText: snap.target.fullText == nil ? nil : value
        )
        return TargetObservation(appIsRunning: true, isSameElement: true, isFocusedInApp: focused, evidence: evidence)
    }
}

/// Replaces exactly the original selection, once, after revalidation, and
/// verifies the result. Never writes to whatever control is merely frontmost.
public final class AccessibilityReplacer: TextReplacing {
    public enum Method { case automatic, pasteboardOnly }
    let method: Method
    let pasteboard: PasteboardAccess

    public init(method: Method = .automatic, pasteboard: PasteboardAccess = SystemPasteboard()) {
        self.method = method
        self.pasteboard = pasteboard
    }

    @MainActor
    public func replace(_ snap: CaptureSnapshot, with text: String) async -> ApplyOutcome {
        guard let handle = snap.handle as? TargetHandle else { return .blocked(.evidenceUnavailable("handle")) }
        if let reason = ReplacementPlanner.check(original: snap.target, now: AccessibilityCapture.observe(snap)) {
            return .blocked(reason)
        }
        let el = handle.element
        if method == .automatic && AX.isSettable(el, "AXSelectedText") {
            return await replaceViaAccessibility(snap, element: el, text: text)
        }
        return await replaceViaPasteboard(snap, handle: handle, text: text)
    }

    @MainActor
    func replaceViaAccessibility(_ snap: CaptureSnapshot, element el: AXUIElement, text: String) async -> ApplyOutcome {
        let err = AX.set(el, "AXSelectedText", text as CFString)
        let result = await verify(snap, element: el, text: text, attempts: err == .success ? 12 : 2)
        switch result {
        case .confirmed: return .confirmed(.accessibilitySelectedText)
        case .unchanged:
            return err == .success
                ? .failed("The app didn't accept the replacement.")
                : .failed("The app rejected the replacement.")
        case .unexpected: return .uncertain("The text changed in an unexpected way.")
        case .unverifiable: return .uncertain("Couldn't confirm the replacement.")
        }
    }

    /// Conservative fallback for controls whose selected text is not writable:
    /// only with readable verification, a revalidated frontmost target and
    /// clipboard ownership checks. The original clipboard is restored only after
    /// a confirmed paste and only if nothing else wrote to it meanwhile.
    @MainActor
    func replaceViaPasteboard(_ snap: CaptureSnapshot, handle: TargetHandle, text: String) async -> ApplyOutcome {
        guard snap.target.fullText != nil || snap.target.selectedRange != nil else {
            return .blocked(.evidenceUnavailable("verification"))
        }
        guard let app = NSRunningApplication(processIdentifier: handle.pid) else { return .blocked(.appClosed) }
        app.activate(options: [])
        for _ in 0..<40 where NSWorkspace.shared.frontmostApplication?.processIdentifier != handle.pid {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == handle.pid else {
            return .blocked(.focusMoved)
        }
        // Revalidate after activation: focus or selection may have moved.
        if let reason = ReplacementPlanner.check(original: snap.target, now: AccessibilityCapture.observe(snap)) {
            return .blocked(reason)
        }
        let tx = ClipboardTransaction(pasteboard: pasteboard)
        tx.writeReplacement(text)
        KeyboardEvents.postCommandV(to: handle.pid)
        let result = await verify(snap, element: handle.element, text: text, attempts: 30)
        switch result {
        case .confirmed:
            _ = tx.finish()
            return .confirmed(.pasteboard)
        case .unchanged:
            // Restoring now could race a paste still in flight; leave the draft on the clipboard.
            return .uncertain("Couldn't confirm the paste. The draft is on your clipboard.")
        case .unexpected, .unverifiable:
            return .uncertain("Couldn't confirm the replacement. The draft is on your clipboard.")
        }
    }

    @MainActor
    func verify(_ snap: CaptureSnapshot, element el: AXUIElement, text: String, attempts: Int) async -> VerificationResult {
        var last: VerificationResult = .unverifiable
        for i in 0..<attempts {
            if i > 0 { try? await Task.sleep(nanoseconds: 50_000_000) }
            let full = snap.target.fullText == nil ? nil : AX.string(el, "AXValue")
            var rangeText: String? = nil
            if full == nil, let r = snap.target.selectedRange {
                rangeText = AX.string(el, for: CFRange(location: r.location, length: (text as NSString).length))
            }
            last = ReplacementPlanner.verify(original: snap.target, replacement: text,
                                             observedFullText: full, observedRangeText: rangeText)
            if last == .confirmed || last == .unexpected { return last }
        }
        return last
    }
}

enum KeyboardEvents {
    static let vKey: CGKeyCode = 0x09
    static let zKey: CGKeyCode = 0x06

    static func postCommandV(to pid: pid_t) { postCommand(vKey, to: pid) }

    static func postCommand(_ key: CGKeyCode, to pid: pid_t?) {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        if let pid {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Post an arbitrary key chord through the HID tap (used by the probe to press a global shortcut).
    static func postChord(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// One key transition through the HID tap; `autorepeat` marks a held key's repeat (probe only).
    static func postKey(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags = [], autorepeat: Bool = false) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down) else { return }
        e.flags = flags
        if autorepeat { e.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        e.post(tap: .cghidEventTap)
    }

    /// Left click at a screen point (top-left origin), probe only.
    static func click(at point: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }

    /// Type text as keyboard input, one character at a time (probe only).
    static func typeText(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in text {
            let units = Array(String(ch).utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                e.post(tap: .cghidEventTap)
            }
            usleep(15_000)
        }
    }
}

/// NSPasteboard adapter that snapshots every item's data for each declared type.
public final class SystemPasteboard: PasteboardAccess {
    let pb: NSPasteboard
    public init(_ pb: NSPasteboard = .general) { self.pb = pb }

    public var changeCount: Int { pb.changeCount }

    public func snapshotItems() -> [PasteboardItemSnapshot] {
        (pb.pasteboardItems ?? []).map { item in
            var map: [String: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { map[t.rawValue] = d } }
            return PasteboardItemSnapshot(dataByType: map)
        }
    }

    public func writePlainText(_ text: String) -> Int {
        pb.clearContents()
        pb.setString(text, forType: .string)
        return pb.changeCount
    }

    public func restore(_ items: [PasteboardItemSnapshot]) -> Int {
        pb.clearContents()
        let restored: [NSPasteboardItem] = items.map { snap in
            let item = NSPasteboardItem()
            for (t, d) in snap.dataByType { item.setData(d, forType: NSPasteboard.PasteboardType(t)) }
            return item
        }
        if !restored.isEmpty { pb.writeObjects(restored) }
        return pb.changeCount
    }
}
#endif
