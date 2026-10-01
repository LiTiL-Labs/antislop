#if os(macOS)
import AntiSlopCore
import AppKit
import SwiftUI

/// Developer-only window, enabled with `--debug-prompts` (or
/// ANTISLOP_DEBUG_PROMPTS=1), that shows the full instructions, request data
/// and raw runtime response of the latest request. Contents live in memory
/// only; nothing here is logged or saved. Not part of ordinary settings.
@MainActor
final class DebugInspector {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("--debug-prompts")
            || ProcessInfo.processInfo.environment["ANTISLOP_DEBUG_PROMPTS"] == "1"
    }

    private let model = DebugInspectorModel()
    private var window: NSWindow?

    /// Start showing a new request; later updates arrive from any thread.
    func show(_ trace: RequestTrace) {
        model.snapshot = trace.snapshot
        trace.onUpdate = { [weak model] s in
            DispatchQueue.main.async { MainActor.assumeIsolated { model?.snapshot = s } }
        }
        let w = window ?? makeWindow()
        window = w
        if !w.isVisible { w.center() }
        // Never take keyboard focus from the panel.
        w.orderFrontRegardless()
    }

    /// Put the inspector beside the panel, on whichever side has room.
    func place(beside panel: NSWindow?) {
        guard let w = window, w.isVisible, let panel, panel.isVisible,
              let screen = panel.screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        var f = w.frame
        f.size.height = min(f.height, v.height)
        f.origin.x = panel.frame.maxX + 12 + f.width <= v.maxX ? panel.frame.maxX + 12 : max(v.minX, panel.frame.minX - 12 - f.width)
        f.origin.y = min(max(panel.frame.maxY - f.height, v.minY), v.maxY - f.height)
        w.setFrame(f, display: true)
    }

    private func makeWindow() -> NSWindow {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 780),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        w.title = "Anti-slop debug — prompt and response"
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.hidesOnDeactivate = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: DebugInspectorView(model: model))
        return w
    }
}

@MainActor
final class DebugInspectorModel: ObservableObject {
    @Published var snapshot: RequestTrace.Snapshot?
}

struct DebugInspectorView: View {
    @ObservedObject var model: DebugInspectorModel

    var body: some View {
        ScrollView {
            if let s = model.snapshot {
                VStack(alignment: .leading, spacing: 14) {
                    Text(summary(s))
                        .font(.system(size: 12, weight: .medium))
                        .textSelection(.enabled)
                    Text(modelLine(s))
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                    Text("Shown for debugging only. Nothing here is logged or saved.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    DebugSection(title: "Raw response (before validation)",
                                 text: s.rawResponse ?? (s.outcome == nil ? "Waiting for the response…" : "(none)"))
                    DebugSection(title: "Instructions (system prompt)", text: s.instructions)
                    DebugSection(title: "Request data (stdin)", text: s.dataMessage)
                    DebugSection(title: "Response schema", text: s.schema ?? "(not sent yet)")
                    DebugSection(title: "Command", text: s.command.isEmpty ? "(not started)" : s.command.joined(separator: "\n"))
                    DebugSection(title: "Runtime output (every stdout event)", text: s.transcript ?? "(none yet)")
                    if let err = s.stderr { DebugSection(title: "Runtime stderr", text: err) }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No request yet.").foregroundColor(.secondary).padding(16)
            }
        }
        .frame(minWidth: 420, minHeight: 300)
    }

    func modelLine(_ s: RequestTrace.Snapshot) -> String {
        let requested = s.requestedModel ?? "runtime default"
        let reasoning = s.requestedReasoning ?? "runtime default"
        let reported = s.reportedModel ?? (s.outcome == nil ? "waiting…" : "not reported by the runtime")
        return "Model requested: \(requested) · Reasoning: \(reasoning) · Model the runtime reported: \(reported)"
    }

    func summary(_ s: RequestTrace.Snapshot) -> String {
        let mode = s.mode == .detect ? "Slop check" : "Rewrite"
        let status = s.outcome.map { o in s.durationMs.map { "\(o) in \($0) ms" } ?? o } ?? "In progress…"
        return "\(mode) · \(s.provider) · \(status)"
    }
}

struct DebugSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text("\(text.count) chars").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .controlSize(.small)
            }
            Text(text)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}
#endif
