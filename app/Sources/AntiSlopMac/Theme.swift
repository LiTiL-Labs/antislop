#if os(macOS)
import AppKit
import SwiftUI

/// Run on the main queue with main-actor isolation (AppKit callbacks, deferred UI work).
func onMainAsync(_ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
}

/// Visual tokens from UX.md (engineering starting values).
enum Theme {
    static func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    static let shell = rgb(0xF7F6F3)
    static let shellNS = NSColor(srgbRed: 0xF7 / 255, green: 0xF6 / 255, blue: 0xF3 / 255, alpha: 1)
    static let editor = Color.white
    static let primaryText = rgb(0x232322)
    static let secondaryText = rgb(0x656563)
    static let border = rgb(0x232322, 0.12)
    static let statusFill = rgb(0xEDECE8)
    static let action = rgb(0x1F1F1E)
    static let actionDisabled = rgb(0xD9D8D4)
    static let ready = rgb(0x2E9D4F)
    static let warning = rgb(0xB5651D)
    static let skeleton = rgb(0xE6E5E1)

    static let panelRadius: CGFloat = 18
    static let editorRadius: CGFloat = 12
    static let panelWidth: CGFloat = 430
    static let editorFont = NSFont.systemFont(ofSize: 15)
    static let editorTextColor = NSColor(srgbRed: 0x23 / 255, green: 0x23 / 255, blue: 0x22 / 255, alpha: 1)

    static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Subtle material behind the warm shell tint; opaque when Reduce Transparency is on.
struct ShellBackground: View {
    let reduceTransparency: Bool
    var body: some View {
        ZStack {
            if !reduceTransparency {
                VisualEffectBlur()
                Theme.shell.opacity(0.9)
            } else {
                Theme.shell
            }
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PrimaryButtonStyle: ButtonStyle {
    let enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(enabled ? .white : Theme.secondaryText)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(enabled ? Theme.action.opacity(configuration.isPressed ? 0.8 : 1) : Theme.actionDisabled)
            )
            .contentShape(Rectangle())
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(Theme.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.6 : 1))
            )
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct IconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .light))
                .foregroundColor(Theme.primaryText)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
#endif
