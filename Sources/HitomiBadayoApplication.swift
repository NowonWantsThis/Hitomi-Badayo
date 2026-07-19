import AppKit
import ObjectiveC.runtime

@objc(HitomiBadayoApplication)
final class HitomiBadayoApplication: NSApplication {
    weak var shortcutController: AppShortcutController?

    static func install() {
        let application = NSApplication.shared
        guard !(application is HitomiBadayoApplication) else { return }
        _ = object_setClass(application, HitomiBadayoApplication.self)
    }

    override func sendEvent(_ event: NSEvent) {
        if Self.isCommandQ(event) {
            terminate(nil)
            return
        }
        if shortcutController?.handle(event) == true {
            return
        }
        super.sendEvent(event)
    }

    override func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        if action == #selector(NSApplication.terminate(_:)) {
            terminate(sender)
            return true
        }
        return super.sendAction(action, to: target, from: sender)
    }

    override func terminate(_ sender: Any?) {
        for window in windows {
            guard let sheet = window.attachedSheet else { continue }
            window.endSheet(sheet, returnCode: .cancel)
            sheet.orderOut(nil)
        }
        if modalWindow != nil {
            abortModal()
        }
        DispatchQueue.main.async { [weak self] in
            self?.finishTermination(sender)
        }
    }

    private func finishTermination(_ sender: Any?) {
        super.terminate(sender)
    }

    private static func isCommandQ(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !event.isARepeat, event.keyCode == 12 else {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.intersection([.command, .option, .control, .shift]) == [.command]
    }
}
