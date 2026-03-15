import AppKit
import CoreGraphics

struct InputSimulator {
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let originalContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulateCmdV()

        // Restore clipboard after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pasteboard.clearContents()
            if let original = originalContents {
                pasteboard.setString(original, forType: .string)
            }
        }
    }

    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        // 0x09 = 'v' key
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
