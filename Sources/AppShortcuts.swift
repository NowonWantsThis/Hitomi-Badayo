import Foundation
import AppKit
import SwiftUI

enum AppShortcutModifier: String, CaseIterable, Codable, Hashable, Identifiable {
    case command
    case option
    case control
    case shift

    var id: String { rawValue }

    var label: String {
        AppLocalization.text(labelKey)
    }

    private var labelKey: String {
        switch self {
        case .command: return "Command"
        case .option: return "Option"
        case .control: return "Control"
        case .shift: return "Shift"
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    static let displayOrder: [AppShortcutModifier] = [.command, .option, .control, .shift]
}

enum AppShortcutKey: String, CaseIterable, Codable, Hashable, Identifiable {
    case none
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case digit0 = "0"
    case digit1 = "1"
    case digit2 = "2"
    case digit3 = "3"
    case digit4 = "4"
    case digit5 = "5"
    case digit6 = "6"
    case digit7 = "7"
    case digit8 = "8"
    case digit9 = "9"
    case grave
    case minus
    case equal
    case comma
    case period
    case slash
    case backslash
    case semicolon
    case apostrophe
    case leftBracket
    case rightBracket
    case space
    case returnKey
    case tab
    case escape
    case backspace
    case forwardDelete
    case home
    case end
    case pageUp
    case pageDown
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow

    var id: String { rawValue }

    var label: String {
        AppLocalization.text(labelKey)
    }

    private var labelKey: String {
        switch self {
        case .none: return "None"
        case .grave: return "Grave"
        case .minus: return "Minus"
        case .equal: return "Equal"
        case .comma: return "Comma"
        case .period: return "Period"
        case .slash: return "Slash"
        case .backslash: return "Backslash"
        case .semicolon: return "Semicolon"
        case .apostrophe: return "Apostrophe"
        case .leftBracket: return "Left Bracket"
        case .rightBracket: return "Right Bracket"
        case .space: return "Space"
        case .returnKey: return "Return"
        case .tab: return "Tab"
        case .escape: return "Escape"
        case .backspace: return "Backspace"
        case .forwardDelete: return "Forward Delete"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .upArrow: return "Up Arrow"
        case .downArrow: return "Down Arrow"
        case .leftArrow: return "Left Arrow"
        case .rightArrow: return "Right Arrow"
        default: return displaySymbol
        }
    }

    var displaySymbol: String {
        switch self {
        case .none: return "None"
        case .grave: return "`"
        case .minus: return "-"
        case .equal: return "="
        case .comma: return ","
        case .period: return "."
        case .slash: return "/"
        case .backslash: return "\\"
        case .semicolon: return ";"
        case .apostrophe: return "'"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .space: return "Space"
        case .returnKey: return "↩"
        case .tab: return "⇥"
        case .escape: return "Esc"
        case .backspace: return "⌫"
        case .forwardDelete: return "⌦"
        case .home: return "↖"
        case .end: return "↘"
        case .pageUp: return "⇞"
        case .pageDown: return "⇟"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .digit0, .digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9:
            return rawValue
        default:
            return rawValue.uppercased()
        }
    }

    var keyEquivalent: KeyEquivalent? {
        switch self {
        case .none:
            return nil
        case .grave:
            return KeyEquivalent(Character("`"))
        case .minus:
            return KeyEquivalent(Character("-"))
        case .equal:
            return KeyEquivalent(Character("="))
        case .comma:
            return KeyEquivalent(Character(","))
        case .period:
            return KeyEquivalent(Character("."))
        case .slash:
            return KeyEquivalent(Character("/"))
        case .backslash:
            return KeyEquivalent(Character("\\"))
        case .semicolon:
            return KeyEquivalent(Character(";"))
        case .apostrophe:
            return KeyEquivalent(Character("'"))
        case .leftBracket:
            return KeyEquivalent(Character("["))
        case .rightBracket:
            return KeyEquivalent(Character("]"))
        case .space:
            return .space
        case .returnKey:
            return .return
        case .tab:
            return .tab
        case .escape:
            return .escape
        case .backspace:
            return .delete
        case .forwardDelete:
            return .deleteForward
        case .home:
            return .home
        case .end:
            return .end
        case .pageUp:
            return .pageUp
        case .pageDown:
            return .pageDown
        case .upArrow:
            return .upArrow
        case .downArrow:
            return .downArrow
        case .leftArrow:
            return .leftArrow
        case .rightArrow:
            return .rightArrow
        default:
            return KeyEquivalent(Character(rawValue))
        }
    }

    static func fromKeyEvent(_ event: NSEvent) -> AppShortcutKey? {
        switch event.keyCode {
        case 0: return .a
        case 1: return .s
        case 2: return .d
        case 3: return .f
        case 4: return .h
        case 5: return .g
        case 6: return .z
        case 7: return .x
        case 8: return .c
        case 9: return .v
        case 11: return .b
        case 12: return .q
        case 13: return .w
        case 14: return .e
        case 15: return .r
        case 16: return .y
        case 17: return .t
        case 18: return .digit1
        case 19: return .digit2
        case 20: return .digit3
        case 21: return .digit4
        case 22: return .digit6
        case 23: return .digit5
        case 24: return .equal
        case 25: return .digit9
        case 26: return .digit7
        case 27: return .minus
        case 28: return .digit8
        case 29: return .digit0
        case 30: return .rightBracket
        case 31: return .o
        case 32: return .u
        case 33: return .leftBracket
        case 34: return .i
        case 35: return .p
        case 36, 76:
            return .returnKey
        case 37: return .l
        case 38: return .j
        case 39: return .apostrophe
        case 40: return .k
        case 41: return .semicolon
        case 42: return .backslash
        case 43: return .comma
        case 44: return .slash
        case 45: return .n
        case 46: return .m
        case 47: return .period
        case 48:
            return .tab
        case 49:
            return .space
        case 50:
            return .grave
        case 51:
            return .backspace
        case 53:
            return .escape
        case 115:
            return .home
        case 116:
            return .pageUp
        case 117:
            return .forwardDelete
        case 119:
            return .end
        case 121:
            return .pageDown
        case 123:
            return .leftArrow
        case 124:
            return .rightArrow
        case 125:
            return .downArrow
        case 126:
            return .upArrow
        default:
            break
        }

        guard let character = event.charactersIgnoringModifiers?.lowercased().first else {
            return nil
        }
        switch character {
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        case "0": return .digit0
        case "1": return .digit1
        case "2": return .digit2
        case "3": return .digit3
        case "4": return .digit4
        case "5": return .digit5
        case "6": return .digit6
        case "7": return .digit7
        case "8": return .digit8
        case "9": return .digit9
        case "`": return .grave
        case "-": return .minus
        case "=": return .equal
        case ",": return .comma
        case ".": return .period
        case "/": return .slash
        case "\\": return .backslash
        case ";": return .semicolon
        case "'": return .apostrophe
        case "[": return .leftBracket
        case "]": return .rightBracket
        default: return nil
        }
    }
}

struct AppShortcut: Codable, Equatable, Hashable {
    var key: AppShortcutKey
    var modifiers: Set<AppShortcutModifier>

    static let none = AppShortcut(key: .none, modifiers: [])

    var isActive: Bool {
        key != .none
    }

    var displayText: String {
        guard isActive else { return "None" }
        let modifierText = AppShortcutModifier.displayOrder
            .filter { modifiers.contains($0) }
            .map(\.symbol)
            .joined()
        return "\(modifierText)\(key.displaySymbol)"
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }

    var keyboardShortcut: KeyboardShortcut? {
        guard let keyEquivalent = key.keyEquivalent else { return nil }
        return KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    func normalized() -> AppShortcut {
        key == .none ? .none : self
    }

    static func fromKeyEvent(_ event: NSEvent) -> AppShortcut? {
        guard let key = AppShortcutKey.fromKeyEvent(event) else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = Set<AppShortcutModifier>()
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return AppShortcut(key: key, modifiers: modifiers).normalized()
    }
}

enum AppShortcutCommand: String, CaseIterable, Codable, Hashable, Identifiable {
    case help
    case settings
    case shortcuts
    case pasteURLs
    case startQueue
    case progressWindow
    case moveSelectedJobsUp
    case moveSelectedJobsDown
    case statistics
    case activityLog
    case historyWindow
    case directories
    case metadataFinder
    case metadataAnalysis
    case searcher
    case browserWindow
    case textViewer
    case outputPreview
    case statusColors
    case fontSettings
    case floatingMonitor
    case duplicateImageFinder
    case clipboardViewer
    case openDuplicateImageFolder
    case artistRecommendations
    case hitomiTaster

    var id: String { rawValue }

    var label: String {
        AppLocalization.text(labelKey)
    }

    private var labelKey: String {
        switch self {
        case .help: return "도움말"
        case .settings: return "설정"
        case .shortcuts: return "단축키"
        case .pasteURLs: return "붙여넣고 다운로드"
        case .startQueue: return "대기열 시작"
        case .progressWindow: return "진행 상황"
        case .moveSelectedJobsUp: return "작업을 위로 이동"
        case .moveSelectedJobsDown: return "작업을 아래로 이동"
        case .statistics: return "정보 및 통계"
        case .activityLog: return "활동 로그"
        case .historyWindow: return "작업 기록"
        case .directories: return "다운로드 폴더"
        case .metadataFinder: return "메타데이터 검색"
        case .metadataAnalysis: return "메타데이터 분석"
        case .searcher: return "검색기"
        case .browserWindow: return "브라우저"
        case .textViewer: return "텍스트 뷰어"
        case .outputPreview: return "결과물 미리보기"
        case .statusColors: return "상태 색상"
        case .fontSettings: return "글꼴"
        case .floatingMonitor: return "플로팅 모니터"
        case .duplicateImageFinder: return "중복 이미지 찾기"
        case .clipboardViewer: return "클립보드 뷰어"
        case .openDuplicateImageFolder: return "중복 이미지 폴더 열기"
        case .artistRecommendations: return "작가 추천"
        case .hitomiTaster: return "Hitomi Taster"
        }
    }

    var detail: String {
        AppLocalization.text(detailKey)
    }

    private var detailKey: String {
        switch self {
        case .help, .settings, .shortcuts:
            return "애플리케이션"
        case .pasteURLs, .startQueue, .moveSelectedJobsUp, .moveSelectedJobsDown:
            return "대기열"
        case .progressWindow, .statistics, .activityLog, .historyWindow:
            return "모니터"
        case .directories, .metadataFinder, .metadataAnalysis, .searcher, .browserWindow, .textViewer, .outputPreview:
            return "도구"
        case .statusColors, .fontSettings:
            return "화면"
        case .floatingMonitor:
            return "모니터"
        case .duplicateImageFinder, .openDuplicateImageFolder:
            return "중복 이미지"
        case .clipboardViewer:
            return "클립보드"
        case .artistRecommendations:
            return "추천"
        case .hitomiTaster:
            return "추천"
        }
    }

    var defaultShortcut: AppShortcut {
        switch self {
        case .help:
            return AppShortcut(key: .slash, modifiers: [.command])
        case .settings:
            return AppShortcut(key: .comma, modifiers: [.command])
        case .shortcuts:
            return .none
        case .pasteURLs:
            return AppShortcut(key: .v, modifiers: [.command])
        case .startQueue:
            return AppShortcut(key: .returnKey, modifiers: [.command])
        case .progressWindow:
            return AppShortcut(key: .p, modifiers: [.command, .option])
        case .moveSelectedJobsUp:
            return AppShortcut(key: .upArrow, modifiers: [.control])
        case .moveSelectedJobsDown:
            return AppShortcut(key: .downArrow, modifiers: [.control])
        case .statistics:
            return AppShortcut(key: .i, modifiers: [.command, .option])
        case .activityLog:
            return AppShortcut(key: .l, modifiers: [.command, .option])
        case .historyWindow:
            return .none
        case .directories:
            return AppShortcut(key: .d, modifiers: [.command, .option])
        case .metadataFinder:
            return AppShortcut(key: .f, modifiers: [.command, .option])
        case .metadataAnalysis:
            return AppShortcut(key: .a, modifiers: [.command, .option])
        case .searcher:
            return AppShortcut(key: .s, modifiers: [.command, .option])
        case .browserWindow:
            return .none
        case .textViewer:
            return .none
        case .outputPreview:
            return .none
        case .statusColors:
            return .none
        case .fontSettings:
            return .none
        case .floatingMonitor:
            return .none
        case .duplicateImageFinder:
            return .none
        case .clipboardViewer:
            return AppShortcut(key: .c, modifiers: [.command, .option])
        case .openDuplicateImageFolder:
            return AppShortcut(key: .o, modifiers: [.command, .shift])
        case .artistRecommendations:
            return AppShortcut(key: .r, modifiers: [.command, .option])
        case .hitomiTaster:
            return .none
        }
    }
}

@MainActor
final class AppShortcutController {
    weak var manager: DownloadManager?

    private var isStarted = false

    init(manager: DownloadManager) {
        self.manager = manager
    }

    func start() {
        guard !isStarted else { return }
        HitomiBadayoApplication.install()
        guard let application = NSApplication.shared as? HitomiBadayoApplication else { return }
        application.shortcutController = self
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }
        if let application = NSApplication.shared as? HitomiBadayoApplication,
           application.shortcutController === self {
            application.shortcutController = nil
        }
        isStarted = false
    }

    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              !event.isARepeat,
              let manager,
              let shortcut = AppShortcut.fromKeyEvent(event) else {
            return false
        }

        if shortcut == AppShortcut(key: .v, modifiers: [.option]) {
            manager.toggleQueueViewMode()
            return true
        }
        if shortcut == AppShortcut(key: .t, modifiers: [.option]) {
            manager.setQueueThumbnailsHidden(!manager.queueThumbnailsHidden)
            return true
        }

        guard let command = Self.command(
                matching: shortcut,
                assignments: manager.appShortcutAssignments
              ) else {
            return false
        }

        if command == .pasteURLs {
            let window = event.window ?? NSApp.keyWindow
            guard MainWindowIdentity.acceptsGlobalPaste(window) else {
                return false
            }
            guard !MainWindowIdentity.hasEditableTextFirstResponder(window) else {
                return false
            }
            guard Self.shouldHandleGlobalPaste(isURLInputFocused: manager.isURLInputFocused) else {
                return false
            }
            return manager.pasteAndDownloadURLs()
        }

        manager.performShortcutCommand(command)
        return true
    }

    static func command(
        matching shortcut: AppShortcut,
        assignments: [AppShortcutCommand: AppShortcut]
    ) -> AppShortcutCommand? {
        let normalized = shortcut.normalized()
        guard normalized.isActive else { return nil }
        return AppShortcutCommand.allCases.first { command in
            (assignments[command] ?? command.defaultShortcut).normalized() == normalized
        }
    }

    static func shouldHandleGlobalPaste(isURLInputFocused: Bool) -> Bool {
        !isURLInputFocused
    }
}

@MainActor
enum AppTerminationCoordinator {
    static func terminate() {
        let application = NSApplication.shared
        for window in application.windows {
            guard let sheet = window.attachedSheet else { continue }
            window.endSheet(sheet, returnCode: .cancel)
            sheet.orderOut(nil)
        }
        if application.modalWindow != nil {
            application.abortModal()
        }
        DispatchQueue.main.async {
            application.terminate(nil)
        }
    }
}

@MainActor
extension DownloadManager {
    func performShortcutCommand(_ command: AppShortcutCommand) {
        switch command {
        case .help:
            showingHelp = true
        case .settings:
            openSettingsWindow()
        case .shortcuts:
            openShortcutSettings()
        case .pasteURLs:
            pasteAndDownloadURLs()
        case .startQueue:
            startQueue()
        case .progressWindow:
            openProgressWindow()
        case .moveSelectedJobsUp:
            moveSelectedJobsUp()
        case .moveSelectedJobsDown:
            moveSelectedJobsDown()
        case .statistics:
            showingStatistics = true
        case .activityLog:
            showingActivityLog = true
        case .historyWindow:
            showingHistoryWindow = true
        case .directories:
            showingDirectories = true
        case .metadataFinder:
            showingMetadataFinder = true
        case .metadataAnalysis:
            showingMetadataAnalysis = true
        case .searcher:
            showingSearcher = true
        case .browserWindow:
            openBrowserWindow()
        case .textViewer:
            openTextViewer()
        case .outputPreview:
            openOutputPreviewForSelectedJobs()
        case .statusColors:
            beginEditingStatusColors()
        case .fontSettings:
            openFontSettings()
        case .floatingMonitor:
            toggleFloatingMonitor()
        case .duplicateImageFinder:
            openDuplicateImageFinder()
        case .clipboardViewer:
            openClipboardViewer()
        case .openDuplicateImageFolder:
            openSelectedDuplicateImageFolder()
        case .artistRecommendations:
            showingArtistRecommendations = true
        case .hitomiTaster:
            openHitomiTaster()
        }
    }
}
