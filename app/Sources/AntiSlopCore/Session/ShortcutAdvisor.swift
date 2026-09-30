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

    /// Factory-default system shortcuts that com.apple.symbolichotkeys omits until changed.
    public static let macOSDefaults: [SystemHotKey] = [
        SystemHotKey(id: 64, keyCode: 0x31, modifiers: [.command]),                    // Spotlight
        SystemHotKey(id: 65, keyCode: 0x31, modifiers: [.command, .option]),           // Finder search
        SystemHotKey(id: 60, keyCode: 0x31, modifiers: [.control]),                    // Previous input source
        SystemHotKey(id: 61, keyCode: 0x31, modifiers: [.control, .option]),           // Next input source
        SystemHotKey(id: 28, keyCode: 0x14, modifiers: [.command, .shift]),            // Screenshot
        SystemHotKey(id: 29, keyCode: 0x14, modifiers: [.command, .shift, .control]),
        SystemHotKey(id: 30, keyCode: 0x15, modifiers: [.command, .shift]),            // Area screenshot
        SystemHotKey(id: 31, keyCode: 0x15, modifiers: [.command, .shift, .control]),
        SystemHotKey(id: 184, keyCode: 0x17, modifiers: [.command, .shift]),           // Screenshot options
        SystemHotKey(id: 32, keyCode: KeyCodes.up, modifiers: [.control]),             // Mission Control
        SystemHotKey(id: 33, keyCode: KeyCodes.down, modifiers: [.control]),           // App windows
        SystemHotKey(id: 79, keyCode: KeyCodes.left, modifiers: [.control]),           // Space left
        SystemHotKey(id: 81, keyCode: KeyCodes.right, modifiers: [.control]),          // Space right
        SystemHotKey(id: 27, keyCode: 0x32, modifiers: [.command]),                    // Next window
        SystemHotKey(id: 98, keyCode: 0x2C, modifiers: [.command, .shift]),            // Help menu
    ]

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
    public static let capsLock = 0x39, fn = 0x3F
    public static let modifierKeyNames: [Int: String] = [
        0x37: "Left ⌘", 0x36: "Right ⌘", 0x38: "Left ⇧", 0x3C: "Right ⇧", 0x3A: "Left ⌥", 0x3D: "Right ⌥",
        0x3B: "Left ⌃", 0x3E: "Right ⌃", 0x39: "Caps Lock", 0x3F: "Fn",
    ]

    // NSEvent.ModifierFlags raw bits: device-independent families, then the
    // device-dependent left/right bits (IOKit NX_DEVICE*KEYMASK).
    static let familyBits: [Int: UInt] = [
        0x38: 0x20000, 0x3C: 0x20000, 0x3B: 0x40000, 0x3E: 0x40000,
        0x3A: 0x80000, 0x3D: 0x80000, 0x37: 0x100000, 0x36: 0x100000, 0x3F: 0x800000,
    ]
    static let sideBits: [Int: UInt] = [
        0x3B: 0x1, 0x38: 0x2, 0x3C: 0x4, 0x37: 0x8, 0x36: 0x10, 0x3A: 0x20, 0x3D: 0x40, 0x3E: 0x2000,
    ]
    static let allFamilies: UInt = 0x20000 | 0x40000 | 0x80000 | 0x100000 | 0x800000

    /// After a flagsChanged event for `keyCode`: is that exact key now down, and
    /// is any other modifier held? Caps Lock is a toggle and is never "held".
    public static func modifierState(keyCode: Int, flags: UInt) -> (isDown: Bool, othersHeld: Bool) {
        guard let family = familyBits[keyCode] else { return (false, flags & allFamilies != 0) }
        let isDown: Bool
        let otherSide: Bool
        if let side = sideBits[keyCode] {
            isDown = flags & side != 0
            let sameFamilySides = sideBits.filter { familyBits[$0.key] == family && $0.key != keyCode }.map(\.value)
            otherSide = sameFamilySides.contains { flags & $0 != 0 }
        } else {
            isDown = flags & family != 0
            otherSide = false
        }
        return (isDown, flags & (allFamilies & ~family) != 0 || otherSide)
    }
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
        if modifiers.isEmpty, let name = modifierKeyNames[keyCode] { return name }
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

    /// `appliesInPanel` is true for the anti-slop key, which also applies the
    /// rewrite while the panel is focused.
    public static func assess(_ b: ShortcutBinding, systemHotKeys: [SystemHotKey], appliesInPanel: Bool = false) -> ShortcutAssessment {
        let mods = b.modifierSet
        var warnings: [String] = []

        if KeyCodes.modifierOnly.contains(b.keyCode) {
            guard b.isLoneModifier else {
                return ShortcutAssessment(blocking: "Press the modifier key on its own, or combine modifiers with another key.", warnings: [])
            }
            return ShortcutAssessment(blocking: nil, warnings: loneModifierWarnings(b))
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
            warnings.append("⌘Return sends messages in some apps; Anti-slop will take it over everywhere.")
        }
        if appliesInPanel && noCommandish && KeyCodes.functionKeys[b.keyCode] == nil {
            warnings.append("Inside the Anti-slop panel, \(b.displayLabel) applies the rewrite instead of typing.")
        }
        return ShortcutAssessment(blocking: nil, warnings: warnings)
    }

    static func loneModifierWarnings(_ b: ShortcutBinding) -> [String] {
        switch b.keyCode {
        case KeyCodes.capsLock:
            return ["Caps Lock still turns capitals on or off each time you press it, and macOS may ignore very quick taps.",
                    "Anti-slop needs Accessibility access to notice a lone key."]
        case KeyCodes.fn:
            return ["If macOS uses Fn/Globe for emoji, dictation or input sources (System Settings › Keyboard), pressing it will do that too.",
                    "Anti-slop needs Accessibility access to notice a lone key."]
        default:
            var out = ["\(b.displayLabel) triggers Anti-slop when you press and release it on its own. Shortcuts that use it with other keys keep working."]
            if [0x37, 0x38].contains(b.keyCode) {
                out.append("\(b.displayLabel) is easy to tap by accident; a right-hand modifier is less likely to trigger Anti-slop by mistake.")
            }
            out.append("Anti-slop needs Accessibility access to notice a lone key.")
            return out
        }
    }
}

/// Recognizes a lone modifier trigger from a stream of modifier changes: the key
/// goes down with nothing else held and comes back up, within `maxHold`, with no
/// other key or modifier in between. Caps Lock reports one change per press, so
/// each change is a press (debounced).
public struct LoneModifierDetector: Equatable, Sendable {
    public let keyCode: Int
    public var maxHold: TimeInterval
    private var pressedAt: Date?
    private var lastCapsPress: Date?

    public init(keyCode: Int, maxHold: TimeInterval = 1.0) {
        self.keyCode = keyCode
        self.maxHold = maxHold
    }

    /// Feed a flagsChanged event (raw NSEvent modifier flags). True means "fire".
    public mutating func flagsChanged(keyCode k: Int, flags: UInt, at now: Date = Date()) -> Bool {
        guard k == keyCode else {
            pressedAt = nil
            return false
        }
        if keyCode == KeyCodes.capsLock {
            if let last = lastCapsPress, now.timeIntervalSince(last) < 0.25 { return false }
            lastCapsPress = now
            return true
        }
        let state = KeyCodes.modifierState(keyCode: k, flags: flags)
        if state.isDown {
            pressedAt = state.othersHeld ? nil : now
            return false
        }
        defer { pressedAt = nil }
        guard let started = pressedAt, !state.othersHeld else { return false }
        return now.timeIntervalSince(started) <= maxHold
    }

    /// Any ordinary key while the modifier is down makes it a combination, not a trigger.
    public mutating func otherKeyDown() {
        pressedAt = nil
    }
}
