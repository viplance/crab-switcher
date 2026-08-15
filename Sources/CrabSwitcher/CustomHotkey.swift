import AppKit
import Carbon

struct CustomHotkey: Codable, Equatable {
    private static let storageKey = "customHotkey"
    private static let relevantFlags: CGEventFlags = [
        .maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn,
    ]

    let keyCode: UInt16
    let modifiers: UInt64
    let isFnOnly: Bool
    let isEject: Bool

    init(keyCode: UInt16, modifiers: UInt64, isFnOnly: Bool = false, isEject: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isFnOnly = isFnOnly
        self.isEject = isEject
    }

    static let fn = CustomHotkey(keyCode: 0, modifiers: 0, isFnOnly: true)
    static let eject = CustomHotkey(keyCode: 0, modifiers: 0, isEject: true)

    var title: String {
        if isFnOnly { return "Fn" }
        if isEject { return "⏏ Eject" }

        let flags = CGEventFlags(rawValue: modifiers)
        var title = ""
        if flags.contains(.maskControl) { title += "⌃" }
        if flags.contains(.maskAlternate) { title += "⌥" }
        if flags.contains(.maskShift) { title += "⇧" }
        if flags.contains(.maskCommand) { title += "⌘" }
        if flags.contains(.maskSecondaryFn) { title += "Fn" }
        return title + Self.keyName(for: keyCode)
    }

    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard !isFnOnly, !isEject, keyCode == self.keyCode else { return false }
        let expected = CGEventFlags(rawValue: modifiers).intersection(Self.relevantFlags)
        return flags.intersection(Self.relevantFlags) == expected
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func load() -> CustomHotkey {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let hotkey = try? JSONDecoder().decode(CustomHotkey.self, from: data)
        else { return .fn }
        return hotkey
    }

    private static func keyName(for keyCode: UInt16) -> String {
        keyNames[keyCode] ?? String(format: "Key%02X", keyCode)
    }

    private static let keyNames: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
        0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x24: "↩", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N",
        0x2E: "M", 0x2F: ".", 0x30: "⇥", 0x31: "Space",
        0x32: "`", 0x33: "⌫", 0x35: "⎋",
        0x3A: "F5", 0x3B: "F6", 0x3C: "F7", 0x3D: "F8",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3",
        0x64: "F8", 0x65: "F9", 0x67: "F11", 0x69: "F13",
        0x6A: "F16", 0x6B: "F14", 0x6D: "F10", 0x6F: "F12",
        0x71: "F15", 0x72: "Help", 0x73: "↖", 0x74: "⇞",
        0x75: "⌦", 0x76: "F4", 0x77: "↘", 0x78: "F2",
        0x79: "⇟", 0x7A: "F1", 0x7B: "←", 0x7C: "→",
        0x7D: "↓", 0x7E: "↑", 0x47: "Clear", 0x4C: "⌅",
        0x41: "Kp.", 0x43: "Kp*", 0x45: "Kp+", 0x4B: "Kp/", 0x4E: "Kp-",
        0x52: "Kp0", 0x53: "Kp1", 0x54: "Kp2", 0x55: "Kp3",
        0x56: "Kp4", 0x57: "Kp5", 0x58: "Kp6", 0x59: "Kp7",
        0x5B: "Kp8", 0x5C: "Kp9", 0x49: "⏏",
    ]
}
