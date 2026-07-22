import AppKit
import ObjectiveC.runtime

@objc(HitomiBadayoApplication)
final class HitomiBadayoApplication: NSApplication {
    private static var stableMainMenuKey: UInt8 = 0
    weak var shortcutController: AppShortcutController?

    private var stableMainMenu: NSMenu? {
        get {
            objc_getAssociatedObject(self, &Self.stableMainMenuKey) as? NSMenu
        }
        set {
            objc_setAssociatedObject(
                self,
                &Self.stableMainMenuKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    static func install() {
        let application = NSApplication.shared
        guard !(application is HitomiBadayoApplication) else { return }
        _ = object_setClass(application, HitomiBadayoApplication.self)
    }

    override var mainMenu: NSMenu? {
        get { super.mainMenu }
        set {
            guard stableMainMenu == nil || newValue === stableMainMenu else { return }
            super.mainMenu = newValue
        }
    }

    func installStableMainMenu(_ menu: NSMenu) {
        stableMainMenu = menu
        super.mainMenu = menu
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
