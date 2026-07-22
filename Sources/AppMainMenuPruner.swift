import AppKit

final class StableApplicationMainMenu: NSMenu {
    private(set) var isStructureLocked = false

    func lockStructure() {
        isStructureLocked = true
    }

    override func addItem(_ newItem: NSMenuItem) {
        guard !isStructureLocked else { return }
        super.addItem(newItem)
    }

    override func insertItem(_ newItem: NSMenuItem, at index: Int) {
        guard !isStructureLocked else { return }
        super.insertItem(newItem, at: index)
    }

    override func removeItem(_ item: NSMenuItem) {
        guard !isStructureLocked else { return }
        super.removeItem(item)
    }

    override func removeItem(at index: Int) {
        guard !isStructureLocked else { return }
        super.removeItem(at: index)
    }

    override func removeAllItems() {
        guard !isStructureLocked else { return }
        super.removeAllItems()
    }
}

private final class LocalizedEditMenuActionForwarder: NSObject, NSMenuItemValidation {
    static let shared = LocalizedEditMenuActionForwarder()

    @objc func performUndo(_ sender: Any?) {
        NSApplication.shared.sendAction(Selector(("undo:")), to: nil, from: sender)
    }

    @objc func performRedo(_ sender: Any?) {
        NSApplication.shared.sendAction(Selector(("redo:")), to: nil, from: sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let undoManager = NSApplication.shared.keyWindow?.firstResponder?.undoManager
        switch menuItem.action {
        case #selector(performUndo(_:)): return undoManager?.canUndo == true
        case #selector(performRedo(_:)): return undoManager?.canRedo == true
        default: return false
        }
    }
}

enum AppMainMenuPruner {
    private static let editActions: Set<String> = [
        "undo:", "redo:", "cut:", "copy:", "paste:", "delete:", "selectAll:"
    ]
    private static let windowActions: Set<String> = [
        "performMiniaturize:", "performZoom:", "toggleFullScreen:", "arrangeInFront:"
    ]
    private static let editMenuSignature = [
        "performUndo:", "performRedo:", "-", "cut:", "copy:", "paste:", "delete:", "selectAll:"
    ]
    private static let windowMenuSignature = [
        "performMiniaturize:", "performZoom:", "toggleFullScreen:", "-", "arrangeInFront:"
    ]

    static func isSimplified(_ mainMenu: NSMenu?) -> Bool {
        guard let mainMenu, mainMenu.items.count == 3 else { return false }
        return containsAction(in: mainMenu.items[1].submenu, matching: editActions) &&
            containsAction(in: mainMenu.items[2].submenu, matching: windowActions)
    }

    static func hasRequiredMenus(_ mainMenu: NSMenu?) -> Bool {
        guard let mainMenu, !mainMenu.items.isEmpty else { return false }
        let hasEdit = mainMenu.items.contains { containsAction(in: $0.submenu, matching: editActions) }
        let hasWindow = mainMenu.items.contains { containsAction(in: $0.submenu, matching: windowActions) }
        return hasEdit && hasWindow
    }

    static func removeExtraneousRootItems(_ mainMenu: NSMenu?) {
        guard let mainMenu, let applicationItem = mainMenu.items.first else { return }
        let editItem = mainMenu.items.first { containsAction(in: $0.submenu, matching: editActions) }
        let windowItem = mainMenu.items.first { containsAction(in: $0.submenu, matching: windowActions) }
        let retained = [applicationItem, editItem, windowItem].compactMap { $0 }

        for item in mainMenu.items where !retained.contains(where: { $0 === item }) {
            mainMenu.removeItem(item)
        }
    }

    static func makeStableMainMenu(from mainMenu: NSMenu?) -> StableApplicationMainMenu? {
        guard let mainMenu else { return nil }
        if let stable = mainMenu as? StableApplicationMainMenu {
            stable.lockStructure()
            return stable
        }

        let stable = StableApplicationMainMenu(title: mainMenu.title)
        stable.autoenablesItems = mainMenu.autoenablesItems
        for item in mainMenu.items {
            mainMenu.removeItem(item)
            stable.addItem(item)
        }
        stable.lockStructure()
        return stable
    }

    static func simplify(
        _ mainMenu: NSMenu?,
        language: AppInterfaceLanguage? = nil
    ) {
        guard let mainMenu, let applicationItem = mainMenu.items.first else { return }
        let editItem = mainMenu.items.first { containsAction(in: $0.submenu, matching: editActions) }
        let windowItem = mainMenu.items.first { containsAction(in: $0.submenu, matching: windowActions) }
        removeExtraneousRootItems(mainMenu)

        if let language {
            localize(
                applicationItem: applicationItem,
                editItem: editItem,
                windowItem: windowItem,
                language: language
            )
        }
    }

    static func localizeTrackedMenu(
        _ menu: NSMenu,
        language: AppInterfaceLanguage,
        appName: String = "Hitomi Badayo"
    ) {
        localizeItems(in: menu, language: language, appName: appName)
    }

    private static func localize(
        applicationItem: NSMenuItem,
        editItem: NSMenuItem?,
        windowItem: NSMenuItem?,
        language: AppInterfaceLanguage
    ) {
        if let editItem {
            let title = AppLocalization.text("Edit", language: language)
            if editItem.title != title {
                editItem.title = title
            }
            let menu = submenu(for: editItem, title: title)
            if menuSignature(menu) != editMenuSignature {
                rebuildEditMenu(menu, language: language)
            }
        }
        if let windowItem {
            let title = AppLocalization.text("Window", language: language)
            if windowItem.title != title {
                windowItem.title = title
            }
            let menu = submenu(for: windowItem, title: title)
            if menuSignature(menu) != windowMenuSignature {
                rebuildWindowMenu(menu, language: language)
            }
        }

        let appName = applicationItem.title.isEmpty ? "Hitomi Badayo" : applicationItem.title
        localizeItems(in: applicationItem.submenu, language: language, appName: appName)
        localizeItems(in: editItem?.submenu, language: language, appName: appName)
        localizeItems(in: windowItem?.submenu, language: language, appName: appName)
    }

    private static func rebuildEditMenu(
        _ menu: NSMenu?,
        language: AppInterfaceLanguage
    ) {
        guard let menu else { return }
        menu.removeAllItems()
        menu.addItem(forwardedEditItem(
            "Undo",
            action: #selector(LocalizedEditMenuActionForwarder.performUndo(_:)),
            key: "z",
            language: language
        ))
        menu.addItem(forwardedEditItem(
            "Redo",
            action: #selector(LocalizedEditMenuActionForwarder.performRedo(_:)),
            key: "z",
            modifiers: [.command, .shift],
            language: language
        ))
        menu.addItem(.separator())
        menu.addItem(actionItem("Cut", action: "cut:", key: "x", language: language))
        menu.addItem(actionItem("Copy", action: "copy:", key: "c", language: language))
        menu.addItem(actionItem("Paste", action: "paste:", key: "v", language: language))
        menu.addItem(actionItem("Delete", action: "delete:", language: language))
        menu.addItem(actionItem("Select All", action: "selectAll:", key: "a", language: language))
    }

    private static func rebuildWindowMenu(
        _ menu: NSMenu?,
        language: AppInterfaceLanguage
    ) {
        guard let menu else { return }
        menu.removeAllItems()
        menu.addItem(actionItem(
            "Minimize",
            action: "performMiniaturize:",
            key: "m",
            language: language
        ))
        menu.addItem(actionItem("Zoom", action: "performZoom:", language: language))
        menu.addItem(actionItem(
            "Enter Full Screen",
            action: "toggleFullScreen:",
            key: "f",
            modifiers: [.command, .control],
            language: language
        ))
        menu.addItem(.separator())
        menu.addItem(actionItem(
            "Bring All to Front",
            action: "arrangeInFront:",
            language: language
        ))
    }

    private static func actionItem(
        _ key: String,
        action: String,
        key keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        language: AppInterfaceLanguage
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: AppLocalization.text(key, language: language),
            action: Selector((action)),
            keyEquivalent: keyEquivalent
        )
        item.target = nil
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    private static func forwardedEditItem(
        _ key: String,
        action: Selector,
        key keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        language: AppInterfaceLanguage
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: AppLocalization.text(key, language: language),
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.target = LocalizedEditMenuActionForwarder.shared
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func localizeItems(
        in menu: NSMenu?,
        language: AppInterfaceLanguage,
        appName: String
    ) {
        guard let menu else { return }
        for item in menu.items {
            if let title = localizedTitle(
                for: item,
                language: language,
                appName: appName
            ), item.title != title {
                item.title = title
            }
            localizeItems(in: item.submenu, language: language, appName: appName)
        }
    }

    private static func submenu(for item: NSMenuItem, title: String) -> NSMenu {
        if let menu = item.submenu {
            if menu.title != title {
                menu.title = title
            }
            return menu
        }
        let menu = NSMenu(title: title)
        item.submenu = menu
        return menu
    }

    private static func menuSignature(_ menu: NSMenu) -> [String] {
        menu.items.map { item in
            if item.isSeparatorItem { return "-" }
            return item.action.map(NSStringFromSelector) ?? ""
        }
    }

    private static func localizedTitle(
        for item: NSMenuItem,
        language: AppInterfaceLanguage,
        appName: String
    ) -> String? {
        let action = item.action.map(NSStringFromSelector) ?? ""
        let key: String?
        switch action {
        case "undo:": key = "Undo"
        case "redo:": key = "Redo"
        case "cut:": key = "Cut"
        case "copy:": key = "Copy"
        case "paste:", "pasteAsPlainText:": key = "Paste"
        case "delete:": key = "Delete"
        case "selectAll:": key = "Select All"
        case "performMiniaturize:": key = "Minimize"
        case "performZoom:": key = "Zoom"
        case "toggleFullScreen:":
            key = NSApplication.shared.keyWindow?.styleMask.contains(.fullScreen) == true
                ? "Exit Full Screen"
                : "Enter Full Screen"
        case "arrangeInFront:": key = "Bring All to Front"
        case "hide:":
            return AppLocalization.format("Hide %@", language: language, appName)
        case "hideOtherApplications:": key = "Hide Others"
        case "unhideAllApplications:": key = "Show All"
        case "terminate:", "terminateHitomiBadayo:":
            return AppLocalization.format("Quit %@", language: language, appName)
        default: key = nil
        }
        return key.map { AppLocalization.text($0, language: language) }
    }

    private static func containsAction(in menu: NSMenu?, matching actions: Set<String>) -> Bool {
        guard let menu else { return false }
        for item in menu.items {
            if let action = item.action, actions.contains(NSStringFromSelector(action)) {
                return true
            }
            if containsAction(in: item.submenu, matching: actions) {
                return true
            }
        }
        return false
    }
}
