import CoreGraphics
import Foundation

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidPress()
    func hotkeyDidRelease()
}

class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var targetKeyCode: CGKeyCode
    private var isPressed = false

    static let keyCodes: [String: CGKeyCode] = [
        "fn": 0x3F,
        "left_option": 0x3A, "right_option": 0x3D,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x63,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F
    ]

    init(hotkey: String = "fn") {
        targetKeyCode = Self.keyCodes[hotkey] ?? 0x3F
    }

    func updateHotkey(_ hotkey: String) {
        targetKeyCode = Self.keyCodes[hotkey] ?? 0x3F
    }

    @discardableResult
    func start() -> Bool {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isPressed = false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .flagsChanged:
            // Modifier keys (fn, option) fire flagsChanged for both press and release.
            // Detect press vs. release by checking whether the key is now held.
            guard keyCode == targetKeyCode else { return }

            // fn key does not appear in flags; use key-code equality only.
            // For option keys, CGEventFlags contains the relevant bit.
            let flags = event.flags
            let isModifierDown: Bool

            if targetKeyCode == 0x3F {
                // fn key: no reliable flag bit; toggle based on our isPressed state
                isModifierDown = !isPressed
            } else if targetKeyCode == 0x3A || targetKeyCode == 0x3D {
                // left/right option
                isModifierDown = flags.contains(.maskAlternate)
            } else {
                isModifierDown = !isPressed
            }

            if isModifierDown && !isPressed {
                isPressed = true
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidPress()
                }
            } else if !isModifierDown && isPressed {
                isPressed = false
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidRelease()
                }
            }

        case .keyDown:
            guard keyCode == targetKeyCode, !isPressed else { return }
            isPressed = true
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyDidPress()
            }

        case .keyUp:
            guard keyCode == targetKeyCode, isPressed else { return }
            isPressed = false
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyDidRelease()
            }

        default:
            break
        }
    }
}
