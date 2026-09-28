#if os(macOS)
import AntiSlopCore
import AppKit
import SwiftUI

enum PanelAction: Hashable {
    case retry, openSettings, copyDraft, useCurrentSelection

    var title: String {
        switch self {
        case .retry: return "Try again"
        case .openSettings: return "Open settings"
        case .copyDraft: return "Copy draft"
        case .useCurrentSelection: return "Use current selection"
        }
    }
}

enum StatusKind: Equatable {
    case working, intent, error
}

/// UI state for the floating panel, derived from the session each time it changes.
@MainActor
final class PanelModel: ObservableObject {
    @Published var statusKind: StatusKind = .working
    @Published var statusText = "Reading context…"
    @Published var draft = ""
    @Published var showsEditor = false
    @Published var editorEditable = false
    @Published var info: String?
    @Published var applyEnabled = false
    @Published var footerText = "⌘ Return to apply"
    @Published var actions: [PanelAction] = []
    @Published var isFixture = false
    @Published var editorHeight: CGFloat = 150
    @Published var focusToken = 0
    @Published var reduceTransparency = Theme.reduceTransparency

    var onApply: () -> Void = {}
    var onClose: () -> Void = {}
    var onSettings: () -> Void = {}
    var onAction: (PanelAction) -> Void = { _ in }
    var onEdit: (String) -> Void = { _ in }
    var onLayoutChange: () -> Void = {}

    private var lastAnnounced: String?

    func update(from session: RewriteSession?) {
        guard let s = session else { return }
        let hadEditor = showsEditor
        isFixture = s.usedFixture
        actions = []
        info = nil
        switch s.phase {
        case .generating:
            statusKind = .working
            statusText = "Rewriting…"
            showsEditor = false
            editorEditable = false
        case .ready:
            statusKind = .intent
            statusText = s.intentLine ?? "Context unclear"
            showsEditor = true
            editorEditable = true
            info = s.isUnchangedProposal ? "No changes needed." : s.note
        case .applying:
            statusKind = .intent
            statusText = s.intentLine ?? "Context unclear"
            showsEditor = true
            editorEditable = false
        case .targetChanged(let reason):
            statusKind = .error
            statusText = reason.message
            showsEditor = true
            editorEditable = true
            actions = [.copyDraft, .useCurrentSelection]
        case .failed(.provider(let f)):
            statusKind = .error
            statusText = f.userMessage
            showsEditor = s.hasDraft
            editorEditable = s.hasDraft
            actions = f == .cancelled ? [] : ([.retry] + (f.suggestsSettings ? [.openSettings] : []))
        case .failed(.applyFailed):
            statusKind = .error
            statusText = "Couldn't replace the original selection. Your draft is safe."
            showsEditor = true
            editorEditable = true
            actions = [.copyDraft]
        case .failed(.applyUncertain(let why)):
            statusKind = .error
            statusText = why + " Your draft is safe."
            showsEditor = true
            editorEditable = true
            actions = [.copyDraft]
        case .failed(.composition(let e)):
            statusKind = .error
            switch e {
            case .selectionTooLong(let n): statusText = CaptureRefusal.tooLong(count: n).message
            case .emptySelection: statusText = CaptureRefusal.noSelection.message
            default: statusText = "Couldn't prepare this selection. Check the writing guide and instructions in settings."
            }
            showsEditor = false
            actions = [.openSettings]
        case .succeeded, .cancelled:
            break
        }
        if s.draft != draft { draft = s.draft }
        switch s.applyAvailability {
        case .enabled:
            applyEnabled = true
            footerText = "⌘ Return to apply"
        case .disabled(let reason):
            applyEnabled = false
            footerText = reason ?? (s.phase == .applying ? "Replacing text…" : "⌘ Return to apply")
        }
        if hadEditor != showsEditor { onLayoutChange() }
        if showsEditor && !hadEditor { focusToken += 1 }
        announceIfNeeded(s)
    }

    /// Announce ready/error state once, without reading the whole draft.
    private func announceIfNeeded(_ s: RewriteSession) {
        let text: String?
        switch s.phase {
        case .ready: text = "Rewrite ready. \(statusText)"
        case .targetChanged, .failed: text = statusText
        default: text = nil
        }
        guard let text, text != lastAnnounced else { return }
        lastAnnounced = text
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func reset() {
        statusKind = .working
        statusText = "Reading context…"
        draft = ""
        showsEditor = false
        editorEditable = false
        info = nil
        actions = []
        applyEnabled = false
        footerText = "⌘ Return to apply"
        lastAnnounced = nil
        editorHeight = 150
        reduceTransparency = Theme.reduceTransparency
    }
}

struct PanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusLine
            editorArea
            if let info = model.info {
                Text(info)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(model.actions, id: \.self) { action in
                        Button(action.title) { model.onAction(action) }.buttonStyle(QuietButtonStyle())
                    }
                    Spacer(minLength: 0)
                }
            }
            footer
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .background(ShellBackground(reduceTransparency: model.reduceTransparency))
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .environment(\.colorScheme, .light)
    }

    var header: some View {
        HStack(spacing: 4) {
            Text("Anti-slop")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(Theme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            IconButton(systemName: "gearshape", label: "Settings", action: model.onSettings)
            Button(action: model.onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(Theme.primaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close without changing the original text")
            .accessibilityLabel("Close")
        }
    }

    var statusLine: some View {
        HStack(spacing: 9) {
            switch model.statusKind {
            case .working:
                ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 16, height: 16)
            case .intent:
                Image(systemName: "doc.text").font(.system(size: 14, weight: .light)).foregroundColor(Theme.secondaryText)
            case .error:
                Image(systemName: "exclamationmark.circle").font(.system(size: 14, weight: .regular)).foregroundColor(Theme.warning)
            }
            Text(model.statusText)
                .font(.system(size: 13))
                .foregroundColor(model.statusKind == .error ? Theme.primaryText : Theme.secondaryText)
                .lineLimit(model.statusKind == .error ? 2 : 1)
                .truncationMode(.tail)
                .help(model.statusText)
            Spacer(minLength: 0)
            if model.isFixture {
                Text("Fixture preview — not live AI")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Theme.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.warning.opacity(0.12)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.statusFill))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    var editorArea: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.editorRadius, style: .continuous).fill(Theme.editor)
            if model.showsEditor {
                DraftEditor(
                    text: Binding(get: { model.draft }, set: { model.draft = $0; model.onEdit($0) }),
                    isEditable: model.editorEditable,
                    contentHeight: Binding(get: { model.editorHeight }, set: { h in
                        if abs(h - model.editorHeight) > 1 { model.editorHeight = h; model.onLayoutChange() }
                    }),
                    focusToken: model.focusToken,
                    onCommandReturn: model.onApply,
                    onEscape: model.onClose
                )
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Capsule().fill(Theme.skeleton).frame(width: 300, height: 13)
                    Capsule().fill(Theme.skeleton).frame(width: 250, height: 13)
                    Capsule().fill(Theme.skeleton).frame(width: 190, height: 13)
                }
                .padding(18)
                .accessibilityHidden(true)
            }
        }
        .frame(height: model.showsEditor ? min(max(model.editorHeight, 120), Self.maxEditorHeight) : 170)
        .clipShape(RoundedRectangle(cornerRadius: Theme.editorRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.editorRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    static var maxEditorHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(160, min(420, visible - 260))
    }

    var footer: some View {
        HStack {
            Text(model.footerText)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.secondaryText)
            Spacer()
            Button("Anti-slop", action: model.onApply)
                .buttonStyle(PrimaryButtonStyle(enabled: model.applyEnabled))
                .disabled(!model.applyEnabled)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Replace the original selection with this text")
                .accessibilityLabel("Anti-slop: replace the original selection")
        }
    }
}

/// Plain-text editor: ordinary Return inserts a newline; Command-Return applies;
/// Escape closes. Automatic substitutions are off so the editor never alters
/// quotes, dashes or spelling behind the writer's back.
struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    @Binding var contentHeight: CGFloat
    var focusToken: Int
    var onCommandReturn: () -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = DraftTextView(frame: NSRect(x: 0, y: 0, width: Theme.panelWidth - 40, height: 100))
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.smartInsertDeleteEnabled = false
        tv.font = Theme.editorFont
        tv.textColor = Theme.editorTextColor
        tv.insertionPointColor = Theme.editorTextColor
        tv.backgroundColor = .white
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.string = text
        tv.delegate = context.coordinator
        tv.onCommandReturn = onCommandReturn
        tv.onEscape = onEscape
        tv.setAccessibilityLabel("Proposed replacement")
        scroll.documentView = tv
        context.coordinator.textView = tv
        let coordinator = context.coordinator
        onMainAsync { coordinator.reportHeight() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? DraftTextView else { return }
        tv.onCommandReturn = onCommandReturn
        tv.onEscape = onEscape
        if tv.string != text {
            tv.string = text
            context.coordinator.reportHeight()
        }
        tv.isEditable = isEditable
        tv.isSelectable = true
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            onMainAsync { tv.window?.makeFirstResponder(tv) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DraftEditor
        weak var textView: NSTextView?
        var lastFocusToken = -1

        init(_ parent: DraftEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            reportHeight()
        }

        func reportHeight() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2 + 6
            // Deferred so SwiftUI state never changes during a view update.
            onMainAsync { [weak self] in
                guard let self, abs(h - self.parent.contentHeight) > 1 else { return }
                self.parent.contentHeight = h
            }
        }
    }
}

final class DraftTextView: NSTextView {
    var onCommandReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let returnKeys: Set<UInt16> = [36, 76]
        if returnKeys.contains(event.keyCode), event.modifierFlags.contains(.command), !hasMarkedText() {
            onCommandReturn?()
            return
        }
        if event.keyCode == 53, !hasMarkedText() { // Escape closes instead of opening completions
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

/// Borderless floating panel that can take keyboard focus.
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    static func make() -> FloatingPanel {
        let p = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 320),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        p.configure()
        return p
    }

    private func configure() {
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setAccessibilityLabel("Anti-slop")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Places, animates and resizes the panel next to the selection.
@MainActor
final class PanelController {
    let model = PanelModel()
    private var panel: FloatingPanel?
    private var hosting: NSHostingView<PanelView>?
    private(set) var placement: PlacementResult?
    /// Incremented on every show, so a hide animation that finishes after a new
    /// show never hides the new panel.
    private var showGeneration = 0

    var isVisible: Bool { panel?.isVisible ?? false }
    var window: NSWindow? { panel }

    init() {
        model.onLayoutChange = { [weak self] in self?.scheduleResize() }
    }

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }
        let p = FloatingPanel.make()
        let host = NSHostingView(rootView: PanelView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 320)
        p.contentView = host
        p.onCancel = { [weak self] in self?.model.onClose() }
        panel = p
        hosting = host
        return p
    }

    func show(anchor: PanelRect?) {
        showGeneration += 1
        let p = ensurePanel()
        let size = hosting?.fittingSize ?? NSSize(width: Theme.panelWidth, height: 320)
        let frames = NSScreen.screens.map { s -> PanelRect in
            let v = s.visibleFrame
            return PanelRect(x: v.minX, y: v.minY, width: v.width, height: v.height)
        }
        let mouse = NSEvent.mouseLocation
        let result = PanelPlacement.place(size: (Double(size.width), Double(size.height)), selection: anchor,
                                          visibleFrames: frames, fallbackPoint: (Double(mouse.x), Double(mouse.y)))
        placement = result
        let final = NSRect(x: result.frame.x, y: result.frame.y, width: result.frame.width, height: result.frame.height)

        // Short slide toward the chosen side plus fade; fade only with Reduce Motion.
        var start = final
        if !Theme.reduceMotion {
            let d: CGFloat = 10
            switch result.side {
            case .right: start.origin.x -= d
            case .left: start.origin.x += d
            case .below: start.origin.y += d
            case .above: start.origin.y -= d
            case .unanchored, .overlapping: start.origin.y -= d / 2
            }
        }
        p.setFrame(start, display: false)
        p.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.19
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
            p.animator().setFrame(final, display: true)
        }
    }

    func focus() {
        guard let p = panel, p.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func hide(completion: (() -> Void)? = nil) {
        guard let p = panel, p.isVisible else { completion?(); return }
        let generation = showGeneration
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Theme.reduceMotion ? 0.08 : 0.12
            p.animator().alphaValue = 0
        }, completionHandler: {
            onMainAsync { [weak self] in
                guard let self, self.showGeneration == generation else { return }
                p.orderOut(nil)
                p.alphaValue = 1
                completion?()
            }
        })
    }

    private var resizeScheduled = false

    private func scheduleResize() {
        guard !resizeScheduled else { return }
        resizeScheduled = true
        onMainAsync { [weak self] in
            self?.resizeScheduled = false
            self?.resizeToFit()
        }
    }

    /// Keep the top edge fixed and stay inside the display's visible frame.
    func resizeToFit() {
        guard let p = panel, let host = hosting, p.isVisible else { return }
        let size = host.fittingSize
        var f = p.frame
        guard abs(f.height - size.height) > 0.5 || abs(f.width - size.width) > 0.5 else { return }
        let top = f.maxY
        f.size = size
        f.origin.y = top - size.height
        if let screen = p.screen ?? NSScreen.main {
            let v = screen.visibleFrame
            f.origin.y = max(f.origin.y, v.minY)
            f.origin.x = min(max(f.origin.x, v.minX), v.maxX - f.width)
        }
        p.setFrame(f, display: true, animate: false)
    }
}

/// Small transient message for refusals ("Select some text first."), shown
/// near the pointer without taking focus from the source app.
@MainActor
final class Toast {
    private var panel: NSPanel?
    private var generation = 0

    func show(_ message: String) {
        let p = panel ?? makePanel()
        panel = p
        let host = NSHostingView(rootView: ToastView(message: message))
        p.contentView = host
        let size = host.fittingSize
        let mouse = NSEvent.mouseLocation
        var frame = NSRect(x: mouse.x + 14, y: mouse.y - size.height - 14, width: size.width, height: size.height)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            frame.origin.x = min(max(frame.minX, v.minX), v.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, v.minY), v.maxY - frame.height)
        }
        p.setFrame(frame, display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        generation += 1
        let g = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let self, self.generation == g else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }
}

struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(Theme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(ShellBackground(reduceTransparency: Theme.reduceTransparency))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .environment(\.colorScheme, .light)
    }
}
#endif
