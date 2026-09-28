import Foundation

/// An enabled macOS system shortcut (from com.apple.symbolichotkeys).
public struct SystemHotKey: Equatable, Sendable {
    public let id: Int
    public let keyCode: Int
    public let modifiers: Set<ShortcutModifier>
    public init(id: Int, keyCode: Int, modifiers: Set<ShortcutModifier>) {
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Convert a symbolic-hotkey modifier mask (NSEvent.ModifierFlags raw bits).
    public static func modifiers(fromMask mask: Int) -> Set<ShortcutModifier> {
        var out = Set<ShortcutModifier>()
        if mask & 0x20000 != 0 { out.insert(.shift) }
        if mask & 0x40000 != 0 { out.insert(.control) }
        if mask & 0x80000 != 0 { out.insert(.option) }
        if mask & 0x100000 != 0 { out.insert(.command) }
        if mask & 0x800000 != 0 { out.insert(.function) }
        return out
    }

    public var name: String { SystemHotKey.names[id] ?? "a macOS keyboard shortcut" }

    static let names: [Int: String] = [
        7: "Move focus to the menu bar", 8: "Move focus to the Dock", 9: "Move focus to the active window",
        10: "Move focus to the window toolbar", 11: "Move focus to the floating window",
        12: "Change the way Tab moves focus", 13: "Turn keyboard access on or off",
        15: "Zoom", 17: "Zoom in", 19: "Zoom out", 21: "Invert colors", 23: "Zoom image smoothing",
        25: "Increase contrast", 26: "Decrease contrast", 27: "Move focus to next window",
        28: "Save picture of screen as a file", 29: "Copy picture of screen",
        30: "Save picture of selected area", 31: "Copy picture of selected area",
        32: "Mission Control", 33: "Application windows", 34: "Mission Control", 35: "Application windows",
        36: "Show Desktop", 37: "Show Desktop", 52: "Turn Dock hiding on/off", 57: "Move focus to status menus",
        59: "VoiceOver", 60: "Select the previous input source", 61: "Select the next input source",
        62: "Dashboard", 64: "Spotlight", 65: "Finder search window", 79: "Move left a space",
        80: "Move left a space", 81: "Move right a space", 82: "Move right a space",
        98: "Show Help menu", 118: "Switch to Desktop 1", 119: "Switch to Desktop 2", 120: "Switch to Desktop 3",
        121: "Switch to Desktop 4", 160: "Launchpad", 162: "Accessibility Controls", 163: "Notification Center",
        175: "Do Not Disturb", 179: "Emoji & Symbols", 184: "Screenshot and recording options", 190: "Quick Note",
        222: "Stage Manager",
    ]
}

public struct ShortcutAssessment: Equatable, Sendable {
    /// Why this key cannot be used; registration must not be attempted.
    public var blocking: String?
    /// Known consequences worth confirming (consumed keys, overridden shortcuts).
    public var warnings: [String]

    public var isUsable: Bool { blocking == nil }
}

public enum KeyCodes {
    public static let returnKey = 0x24, tab = 0x30, space = 0x31, delete = 0x33, escape = 0x35
    public static let forwardDelete = 0x75, home = 0x73, end = 0x77, pageUp = 0x74, pageDown = 0x79
    public static let left = 0x7B, right = 0x7C, down = 0x7D, up = 0x7E, keypadEnter = 0x4C, help = 0x72
    public static let modifierOnly: Set<Int> = [0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F]
    public static let capsLock = 0x39
    public static let mediaKeys: Set<Int> = [0x48, 0x49, 0x4A]
    public static let functionKeys: [Int: String] = [
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
    ]
    /// Keys for which macOS itself reports the function flag; it is not a user modifier.
    public static var implicitFunctionFlag: Set<Int> {
        Set(functionKeys.keys).union([forwardDelete, home, end, pageUp, pageDown, left, right, down, up, help])
    }

    public static let specialNames: [Int: String] = [
        returnKey: "Return", tab: "Tab", space: "Space", delete: "Delete", escape: "Escape",
        forwardDelete: "Forward Delete", home: "Home", end: "End", pageUp: "Page Up", pageDown: "Page Down",
        left: "←", right: "→", down: "↓", up: "↑", keypadEnter: "Enter", help: "Help",
    ]

    public static func label(keyCode: Int, character: String?, modifiers: [ShortcutModifier]) -> String {
        let mods = ShortcutModifier.displayOrder.filter { modifiers.contains($0) }.map(\.symbol).joined()
        let key = functionKeys[keyCode] ?? specialNames[keyCode]
            ?? character.map { $0.uppercased() }.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Key \(keyCode)"
        return mods + key
    }
}

/// Assess a recorded binding against real OS limits and known conflicts. It
/// does not claim universal conflict detection: unknown app-specific shortcuts
/// cannot be discovered.
public enum ShortcutAdvisor {
    static let hardReserved: [(Int, Set<ShortcutModifier>, String)] = [
        (KeyCodes.tab, [.command], "⌘Tab switches apps and can't be reassigned."),
        (KeyCodes.tab, [.command, .shift], "⇧⌘Tab switches apps and can't be reassigned."),
        (KeyCodes.escape, [.command, .option], "⌥⌘Escape opens Force Quit and can't be reassigned."),
        (0x0C, [.control, .command], "⌃⌘Q locks the screen and can't be reassigned."),
    ]

    static let commonAppShortcuts: [Int: String] = [
        0x08: "Copy", 0x09: "Paste", 0x07: "Cut", 0x06: "Undo", 0x00: "Select All", 0x01: "Save",
        0x0C: "Quit", 0x0D: "Close Window", 0x2D: "New", 0x1F: "Open", 0x23: "Print", 0x03: "Find",
        0x11: "New Tab", 0x04: "Hide", 0x2E: "Minimize",
    ]

    public static func assess(_ b: ShortcutBinding, systemHotKeys: [SystemHotKey]) -> ShortcutAssessment {
        let mods = b.modifierSet
        var warnings: [String] = []

        if KeyCodes.modifierOnly.contains(b.keyCode) {
            return ShortcutAssessment(blocking: "A modifier key alone can't be a shortcut. Add another key.", warnings: [])
        }
        if KeyCodes.mediaKeys.contains(b.keyCode) {
            return ShortcutAssessment(blocking: "Volume and media keys can't be assigned.", warnings: [])
        }
        if mods.contains(.function) {
            return ShortcutAssessment(blocking: "macOS doesn't let apps register Fn/Globe combinations. Choose another key.", warnings: [])
        }
        for (code, set, why) in hardReserved where code == b.keyCode && set == mods {
            return ShortcutAssessment(blocking: why, warnings: [])
        }
        if let sys = systemHotKeys.first(where: { $0.keyCode == b.keyCode && $0.modifiers == mods }) {
            return ShortcutAssessment(
                blocking: "macOS uses \(b.displayLabel) for \(sys.name). Choose another key, or turn that shortcut off in System Settings › Keyboard › Keyboard Shortcuts.",
                warnings: [])
        }

        let noCommandish = mods.isDisjoint(with: [.command, .control, .option])
        if noCommandish {
            if KeyCodes.functionKeys[b.keyCode] != nil {
                if mods.isEmpty {
                    warnings.append("On many Mac keyboards F-keys control brightness or volume. If \(b.displayLabel) doesn't trigger Anti-slop, hold Fn or turn on “Use F1, F2, etc. keys as standard function keys”.")
                }
            } else if b.keyCode == KeyCodes.escape {
                warnings.append("Escape will trigger Anti-slop instead of closing dialogs or cancelling in other apps.")
            } else {
                warnings.append("\(b.displayLabel) will trigger Anti-slop instead of typing or acting in other apps while Anti-slop is running.")
            }
        }
        if mods == [.command], let what = commonAppShortcuts[b.keyCode] {
            warnings.append("\(b.displayLabel) is \(what) in most apps; Anti-slop will take it over everywhere.")
        }
        if b.keyCode == KeyCodes.returnKey && mods == [.command] {
            warnings.append("⌘Return also applies the rewrite inside the Anti-slop panel, and sends messages in some apps.")
        }
        return ShortcutAssessment(blocking: nil, warnings: warnings)
    }
}
