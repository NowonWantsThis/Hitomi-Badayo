import AppKit

private final class StableRootMenuItem: NSMenuItem {
    private var lockedTitle: String?

    override var title: String {
        get { super.title }
        set { super.title = lockedTitle ?? newValue }
    }

    func lockTitle(_ title: String) {
        lockedTitle = title
        if super.title != title {
            super.title = title
        }
    }
}

final class StableApplicationMainMenu: NSMenu {
    private(set) var isStructureLocked = false
    private var lockedRootTitles: [ObjectIdentifier: String] = [:]
    private var rootTitleObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var lockedSubmenuTitles: [ObjectIdentifier: String] = [:]
    private var submenuTitleObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    func lockStructure() {
        isStructureLocked = true
    }

    func lockRootTitles(_ entries: [(item: NSMenuItem, title: String)]) {
        for entry in entries {
            lockedRootTitles[ObjectIdentifier(entry.item)] = entry.title
            if let submenu = entry.item.submenu {
                lockedSubmenuTitles[ObjectIdentifier(submenu)] = entry.title
            }
        }

        for entry in entries {
            let identifier = ObjectIdentifier(entry.item)
            if let stableItem = entry.item as? StableRootMenuItem {
                stableItem.lockTitle(entry.title)
            } else if rootTitleObservations[identifier] == nil {
                rootTitleObservations[identifier] = entry.item.observe(\.title, options: [.new]) {
                    [weak self, weak item = entry.item] _, _ in
                    guard let self,
                          let item,
                          let lockedTitle = self.lockedRootTitles[identifier],
                          item.title != lockedTitle else {
                        return
                    }
                    item.title = lockedTitle
                }
            }
            if !(entry.item is StableRootMenuItem), entry.item.title != entry.title {
                entry.item.title = entry.title
            }

            guard let submenu = entry.item.submenu else { continue }
            let submenuIdentifier = ObjectIdentifier(submenu)
            if submenuTitleObservations[submenuIdentifier] == nil {
                submenuTitleObservations[submenuIdentifier] = submenu.observe(\.title, options: [.new]) {
                    [weak self, weak submenu] _, _ in
                    guard let self,
                          let submenu,
                          let lockedTitle = self.lockedSubmenuTitles[submenuIdentifier],
                          submenu.title != lockedTitle else {
                        return
                    }
                    submenu.title = lockedTitle
                }
            }
            if submenu.title != entry.title {
                submenu.title = entry.title
            }
        }
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

@MainActor
private final class LocalizedEditMenuActionForwarder: NSObject, NSMenuItemValidation, NSMenuDelegate {
    static let shared = LocalizedEditMenuActionForwarder()

    weak var manager: DownloadManager?

    var usesQueueCommands: Bool {
        let window = NSApplication.shared.keyWindow
        return MainWindowIdentity.acceptsGlobalPaste(window) &&
            !MainWindowIdentity.hasEditableTextFirstResponder(window)
    }

    func configure(manager: DownloadManager) {
        self.manager = manager
    }

    func menuWillOpen(_ menu: NSMenu) {
        AppMainMenuPruner.updateEditMenuPresentation(
            menu,
            language: manager?.settingsStore.interfaceLanguage ?? .english
        )
    }

    @objc func performUndo(_ sender: Any?) {
        NSApplication.shared.sendAction(Selector(("undo:")), to: nil, from: sender)
    }

    @objc func performRedo(_ sender: Any?) {
        NSApplication.shared.sendAction(Selector(("redo:")), to: nil, from: sender)
    }

    @objc func performCut(_ sender: Any?) {
        performStandardAction("cut:", sender: sender)
    }

    @objc func performCopy(_ sender: Any?) {
        if usesQueueCommands {
            _ = manager?.copyEditMenuSelection()
        } else {
            performStandardAction("copy:", sender: sender)
        }
    }

    @objc func performPaste(_ sender: Any?) {
        if usesQueueCommands {
            _ = manager?.pasteEditMenuURLs()
        } else {
            performStandardAction("paste:", sender: sender)
        }
    }

    @objc func performDelete(_ sender: Any?) {
        if usesQueueCommands {
            _ = manager?.beginRemovingEditMenuSelection()
        } else {
            performStandardAction("delete:", sender: sender)
        }
    }

    @objc func performSelectAll(_ sender: Any?) {
        if usesQueueCommands {
            _ = manager?.selectAllVisibleJobsFromEditMenu()
        } else {
            performStandardAction("selectAll:", sender: sender)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if usesQueueCommands {
            switch menuItem.action {
            case #selector(performCopy(_:)):
                return manager?.canCopyEditMenuSelection == true
            case #selector(performPaste(_:)):
                return manager?.canPasteEditMenuURLs == true
            case #selector(performDelete(_:)):
                return manager?.canRemoveEditMenuSelection == true
            case #selector(performSelectAll(_:)):
                return manager?.canSelectAllVisibleJobsFromEditMenu == true
            default:
                return false
            }
        }

        let undoManager = NSApplication.shared.keyWindow?.firstResponder?.undoManager
        switch menuItem.action {
        case #selector(performUndo(_:)): return undoManager?.canUndo == true
        case #selector(performRedo(_:)): return undoManager?.canRedo == true
        case #selector(performCut(_:)):
            return validatesStandardAction("cut:", menuItem: menuItem)
        case #selector(performCopy(_:)):
            return validatesStandardAction("copy:", menuItem: menuItem)
        case #selector(performPaste(_:)):
            return validatesStandardAction("paste:", menuItem: menuItem)
        case #selector(performDelete(_:)):
            return validatesStandardAction("delete:", menuItem: menuItem)
        case #selector(performSelectAll(_:)):
            return validatesStandardAction("selectAll:", menuItem: menuItem)
        default:
            return false
        }
    }

    private func performStandardAction(_ action: String, sender: Any?) {
        NSApplication.shared.sendAction(
            Selector((action)),
            to: nil,
            from: sender
        )
    }

    private func validatesStandardAction(
        _ action: String,
        menuItem: NSMenuItem
    ) -> Bool {
        let selector = Selector((action))
        guard let target = NSApplication.shared.target(
            forAction: selector,
            to: nil,
            from: menuItem
        ) else {
            return false
        }

        let validationItem = NSMenuItem(
            title: menuItem.title,
            action: selector,
            keyEquivalent: menuItem.keyEquivalent
        )
        if let validator = target as? NSMenuItemValidation {
            return validator.validateMenuItem(validationItem)
        }
        if let validator = target as? NSUserInterfaceValidations {
            return validator.validateUserInterfaceItem(validationItem)
        }
        return true
    }
}

@MainActor
enum AppMainMenuPruner {
    private static let editActions: Set<String> = [
        "undo:", "redo:", "cut:", "copy:", "paste:", "delete:", "selectAll:",
        "performUndo:", "performRedo:", "performCut:", "performCopy:",
        "performPaste:", "performDelete:", "performSelectAll:"
    ]
    private static let windowActions: Set<String> = [
        "performMiniaturize:", "performZoom:", "toggleFullScreen:", "arrangeInFront:"
    ]
    private static let editMenuSignature = [
        "performUndo:", "performRedo:", "-", "performCut:", "performCopy:",
        "performPaste:", "performDelete:", "performSelectAll:"
    ]
    private static let windowMenuSignature = [
        "performMiniaturize:", "performZoom:", "toggleFullScreen:", "-", "arrangeInFront:"
    ]

    static func isSimplified(_ mainMenu: NSMenu?) -> Bool {
        guard let mainMenu, mainMenu.items.count == 3 else { return false }
        return containsAction(in: mainMenu.items[1].submenu, matching: editActions) &&
            containsAction(in: mainMenu.items[2].submenu, matching: windowActions)
    }

    static func configureEditCommands(manager: DownloadManager) {
        LocalizedEditMenuActionForwarder.shared.configure(manager: manager)
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
            let replacement = StableRootMenuItem(
                title: item.title,
                action: item.action,
                keyEquivalent: item.keyEquivalent
            )
            replacement.target = item.target
            replacement.keyEquivalentModifierMask = item.keyEquivalentModifierMask
            replacement.tag = item.tag
            replacement.state = item.state
            replacement.isEnabled = item.isEnabled
            replacement.isHidden = item.isHidden
            replacement.image = item.image
            replacement.toolTip = item.toolTip
            replacement.representedObject = item.representedObject
            let submenu = item.submenu
            item.submenu = nil
            replacement.submenu = submenu
            mainMenu.removeItem(item)
            stable.addItem(replacement)
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
            (mainMenu as? StableApplicationMainMenu)?.lockRootTitles([
                (applicationItem, applicationItem.title),
                (editItem, AppLocalization.text("Edit", language: language)),
                (windowItem, AppLocalization.text("Window", language: language))
            ].compactMap { item, title in
                item.map { (item: $0, title: title) }
            })
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
        updateTrackedEditMenuPresentation(in: menu, language: language)
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
            menu.delegate = LocalizedEditMenuActionForwarder.shared
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
        if let editMenu = editItem?.submenu {
            updateEditMenuPresentation(editMenu, language: language)
        }
    }

    private static func rebuildEditMenu(
        _ menu: NSMenu?,
        language: AppInterfaceLanguage
    ) {
        guard let menu else { return }
        menu.removeAllItems()
        menu.delegate = LocalizedEditMenuActionForwarder.shared
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
        menu.addItem(forwardedEditItem(
            "Cut",
            action: #selector(LocalizedEditMenuActionForwarder.performCut(_:)),
            key: "x",
            language: language
        ))
        menu.addItem(forwardedEditItem(
            "Copy",
            action: #selector(LocalizedEditMenuActionForwarder.performCopy(_:)),
            key: "c",
            language: language
        ))
        menu.addItem(forwardedEditItem(
            "Paste",
            action: #selector(LocalizedEditMenuActionForwarder.performPaste(_:)),
            key: "v",
            language: language
        ))
        menu.addItem(forwardedEditItem(
            "Delete",
            action: #selector(LocalizedEditMenuActionForwarder.performDelete(_:)),
            key: "",
            language: language
        ))
        menu.addItem(forwardedEditItem(
            "Select All",
            action: #selector(LocalizedEditMenuActionForwarder.performSelectAll(_:)),
            key: "a",
            language: language
        ))
    }

    fileprivate static func updateEditMenuPresentation(
        _ menu: NSMenu,
        language: AppInterfaceLanguage
    ) {
        let queueMode = LocalizedEditMenuActionForwarder.shared.usesQueueCommands
        for item in menu.items {
            if item.isSeparatorItem {
                item.isHidden = queueMode
                continue
            }

            let action = item.action.map(NSStringFromSelector) ?? ""
            switch action {
            case "performUndo:", "performRedo:", "performCut:":
                item.isHidden = queueMode
            case "performCopy:":
                item.isHidden = false
                item.title = AppLocalization.text(
                    queueMode ? "Copy Link Address" : "Copy",
                    language: language
                )
            case "performPaste:":
                item.isHidden = false
                item.title = AppLocalization.text(
                    queueMode ? "Paste and Download" : "Paste",
                    language: language
                )
            case "performDelete:":
                item.isHidden = false
                item.title = AppLocalization.text(
                    queueMode ? "Remove from List Only" : "Delete",
                    language: language
                )
            case "performSelectAll:":
                item.isHidden = false
                item.title = AppLocalization.text(
                    "Select All",
                    language: language
                )
            default:
                break
            }
        }
    }

    private static func updateTrackedEditMenuPresentation(
        in menu: NSMenu,
        language: AppInterfaceLanguage
    ) {
        let directlyContainsEditActions = menu.items.contains { item in
            guard let action = item.action else { return false }
            return editActions.contains(NSStringFromSelector(action))
        }
        if directlyContainsEditActions {
            updateEditMenuPresentation(menu, language: language)
        }
        for item in menu.items {
            if let submenu = item.submenu {
                updateTrackedEditMenuPresentation(
                    in: submenu,
                    language: language
                )
            }
        }
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
        case "undo:", "performUndo:": key = "Undo"
        case "redo:", "performRedo:": key = "Redo"
        case "cut:", "performCut:": key = "Cut"
        case "copy:", "performCopy:": key = "Copy"
        case "paste:", "pasteAsPlainText:", "performPaste:": key = "Paste"
        case "delete:", "performDelete:": key = "Delete"
        case "selectAll:", "performSelectAll:": key = "Select All"
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
