import Foundation

enum LocalAPIRoute: Equatable {
    case preflight
    case staticAsset
    case login
    case index
    case webUI
    case docs
    case aboutPage
    case aboutObject
    case helpPage
    case helpObject
    case list
    case view
    case file
    case thumbnail
    case events
    case webSocket
    case status
    case logPage
    case logObject
    case clearLog
    case directoriesPage
    case directoriesObject
    case finderPage
    case finderObject
    case analysisPage
    case analysisObject
    case statistics
    case version
    case count
    case items
    case historyPage
    case historyObject
    case requeueHistory
    case removeHistory
    case clearHistory
    case searchPage
    case search
    case searchProviders
    case enqueueSearch
    case clipboardPage
    case clipboardObject
    case enqueueClipboard
    case watchClipboard
    case browserPage
    case browserObject
    case openBrowser
    case textPage
    case text
    case pageSelectorPage
    case pageSelectorObject
    case updatePageSelector
    case item
    case originalNames
    case names
    case types
    case headers
    case info
    case pdf
    case archive
    case download
    case execute
    case start
    case stop
    case pause
    case resume
    case aria2Limits
    case aria2FileSelection
    case aria2Seeding
    case aria2FileList
    case aria2Peers
    case clear
    case complete
    case comment
    case save
    case updateCookies
    case remove
    case delete
    case deleteFile
    case notFound
}

struct LocalAPIRouter {
    func route(for request: LocalHTTPRequest) -> LocalAPIRoute {
        let method = request.method.uppercased()
        let path = request.path.lowercased()

        if method == "OPTIONS" {
            return .preflight
        }
        if method == "GET", isStaticAssetPath(path) {
            return .staticAsset
        }
        if path == "/login" || path == "/api/login" {
            return .login
        }

        switch (method, path) {
        case ("GET", "/"):
            return .index
        case ("GET", "/webui"), ("GET", "/api/webui"):
            return .webUI
        case ("GET", "/docs"), ("GET", "/docs.html"), ("GET", "/api/docs"):
            return .docs
        case ("GET", "/about"):
            return .aboutPage
        case ("GET", "/api/about"):
            return .aboutObject
        case ("GET", "/help"), ("GET", "/help.html"):
            return .helpPage
        case ("GET", "/api/help"):
            return .helpObject
        case ("GET", "/list"), ("GET", "/api/list"):
            return .list
        case ("GET", "/view"), ("GET", "/api/view"),
             ("GET", "/viewer"), ("GET", "/api/viewer"),
             ("GET", "/reader"), ("GET", "/api/reader"):
            return .view
        case ("GET", "/file"), ("GET", "/api/file"),
             ("GET", "/download_file"), ("GET", "/api/download_file"),
             ("HEAD", "/file"), ("HEAD", "/api/file"),
             ("HEAD", "/download_file"), ("HEAD", "/api/download_file"):
            return .file
        case ("GET", "/thumb"), ("GET", "/api/thumb"):
            return .thumbnail
        case ("GET", "/events"), ("GET", "/api/events"):
            return .events
        case ("GET", "/ws"), ("GET", "/api/ws"),
             ("GET", "/websocket"), ("GET", "/api/websocket"):
            return .webSocket
        case ("GET", "/status"), ("GET", "/api/status"):
            return .status
        case ("GET", "/log"):
            return .logPage
        case ("GET", "/api/log"):
            return .logObject
        case ("POST", "/log/clear"), ("POST", "/api/log/clear"):
            return .clearLog
        case ("GET", "/dirs"), ("GET", "/directories"):
            return .directoriesPage
        case ("GET", "/api/dirs"), ("GET", "/api/directories"):
            return .directoriesObject
        case ("GET", "/finder"):
            return .finderPage
        case ("GET", "/api/finder"):
            return .finderObject
        case ("GET", "/analysis"), ("GET", "/anal"):
            return .analysisPage
        case ("GET", "/api/analysis"), ("GET", "/api/anal"):
            return .analysisObject
        case ("GET", "/stats"), ("GET", "/api/stats"),
             ("GET", "/statistics"), ("GET", "/api/statistics"),
             ("GET", "/stat"), ("GET", "/api/stat"):
            return .statistics
        case ("GET", "/version"), ("GET", "/api/version"):
            return .version
        case ("GET", "/count"), ("GET", "/api/count"):
            return .count
        case ("GET", "/items"), ("GET", "/api/items"):
            return .items
        case ("GET", "/history"):
            return .historyPage
        case ("GET", "/api/history"):
            return .historyObject
        case ("POST", "/history/requeue"), ("POST", "/api/history/requeue"),
             ("POST", "/history/enqueue"), ("POST", "/api/history/enqueue"):
            return .requeueHistory
        case ("POST", "/history/remove"), ("POST", "/api/history/remove"):
            return .removeHistory
        case ("POST", "/history/clear"), ("POST", "/api/history/clear"):
            return .clearHistory
        case ("GET", "/search"):
            return .searchPage
        case ("GET", "/api/search"):
            return .search
        case ("GET", "/search/providers"), ("GET", "/api/search/providers"):
            return .searchProviders
        case ("GET", "/search/enqueue"), ("GET", "/api/search/enqueue"),
             ("POST", "/search/enqueue"), ("POST", "/api/search/enqueue"):
            return .enqueueSearch
        case ("GET", "/clipboard"), ("GET", "/clip"), ("GET", "/clip_viewer"):
            return .clipboardPage
        case ("GET", "/api/clipboard"), ("GET", "/api/clip"):
            return .clipboardObject
        case ("POST", "/clipboard/enqueue"), ("POST", "/api/clipboard/enqueue"),
             ("POST", "/clip/enqueue"), ("POST", "/api/clip/enqueue"),
             ("POST", "/clip_viewer/enqueue"):
            return .enqueueClipboard
        case ("POST", "/clipboard/watch"), ("POST", "/api/clipboard/watch"),
             ("POST", "/clip/watch"), ("POST", "/api/clip/watch"),
             ("POST", "/clip_viewer/watch"):
            return .watchClipboard
        case ("GET", "/browser"), ("GET", "/mybrowser"):
            return .browserPage
        case ("GET", "/api/browser"), ("GET", "/api/mybrowser"):
            return .browserObject
        case ("POST", "/browser/open"), ("POST", "/api/browser/open"),
             ("POST", "/mybrowser/open"), ("POST", "/api/mybrowser/open"):
            return .openBrowser
        case ("GET", "/text"), ("GET", "/text_viewer"), ("GET", "/textviewer"),
             ("GET", "/text_browser"), ("GET", "/textbrowser"):
            return .textPage
        case ("GET", "/api/text"), ("GET", "/api/text_viewer"),
             ("GET", "/api/textviewer"), ("GET", "/api/text_browser"),
             ("GET", "/api/textbrowser"):
            return .text
        case ("GET", "/page_selector"), ("GET", "/page-selector"),
             ("GET", "/select_pages"), ("GET", "/select-pages"),
             ("GET", "/selector"), ("GET", "/pages"):
            return .pageSelectorPage
        case ("GET", "/api/page_selector"), ("GET", "/api/page-selector"),
             ("GET", "/api/select_pages"), ("GET", "/api/select-pages"),
             ("GET", "/api/selector"), ("GET", "/api/pages"):
            return .pageSelectorObject
        case ("POST", "/page_selector"), ("POST", "/api/page_selector"),
             ("POST", "/page-selector"), ("POST", "/api/page-selector"),
             ("POST", "/select_pages"), ("POST", "/api/select_pages"),
             ("POST", "/select-pages"), ("POST", "/api/select-pages"),
             ("POST", "/selector"), ("POST", "/api/selector"),
             ("POST", "/pages"), ("POST", "/api/pages"):
            return .updatePageSelector
        case ("GET", "/item"), ("GET", "/api/item"):
            return .item
        case ("GET", "/names"):
            return .originalNames
        case ("GET", "/api/names"):
            return .names
        case ("GET", "/types"), ("GET", "/api/types"),
             ("POST", "/types"), ("POST", "/api/types"):
            return .types
        case ("GET", "/headers"), ("GET", "/api/headers"):
            return .headers
        case ("GET", "/info"), ("GET", "/api/info"),
             ("GET", "/metadata"), ("GET", "/api/metadata"):
            return .info
        case ("GET", "/pdf"), ("GET", "/api/pdf"),
             ("GET", "/pdf_converter"), ("GET", "/api/pdf_converter"),
             ("POST", "/pdf"), ("POST", "/api/pdf"),
             ("POST", "/pdf_converter"), ("POST", "/api/pdf_converter"):
            return .pdf
        case ("GET", "/zip"), ("GET", "/api/zip"),
             ("GET", "/cbz"), ("GET", "/api/cbz"),
             ("GET", "/archive"), ("GET", "/api/archive"),
             ("POST", "/zip"), ("POST", "/api/zip"),
             ("POST", "/cbz"), ("POST", "/api/cbz"),
             ("POST", "/archive"), ("POST", "/api/archive"):
            return .archive
        case ("GET", "/download"), ("GET", "/api/download"),
             ("POST", "/download"), ("POST", "/api/download"):
            return .download
        case ("GET", "/exec_"), ("GET", "/api/exec_"),
             ("POST", "/exec_"), ("POST", "/api/exec_"):
            return .execute
        case ("POST", "/start"), ("POST", "/api/start"):
            return .start
        case ("POST", "/stop"), ("POST", "/api/stop"):
            return .stop
        case ("POST", "/pause"), ("POST", "/api/pause"):
            return .pause
        case ("POST", "/resume"), ("POST", "/api/resume"):
            return .resume
        case ("POST", "/aria2_limits"), ("POST", "/api/aria2_limits"):
            return .aria2Limits
        case ("POST", "/aria2_files"), ("POST", "/api/aria2_files"),
             ("POST", "/aria2_select"), ("POST", "/api/aria2_select"):
            return .aria2FileSelection
        case ("POST", "/aria2_seed"), ("POST", "/api/aria2_seed"),
             ("POST", "/aria2_seeding"), ("POST", "/api/aria2_seeding"),
             ("POST", "/set_seedings"), ("POST", "/setseedings"):
            return .aria2Seeding
        case ("GET", "/aria2_file_list"), ("GET", "/api/aria2_file_list"),
             ("POST", "/aria2_file_list"), ("POST", "/api/aria2_file_list"),
             ("GET", "/aria2_files_list"), ("GET", "/api/aria2_files_list"),
             ("POST", "/aria2_files_list"), ("POST", "/api/aria2_files_list"),
             ("GET", "/show_files"), ("POST", "/show_files"),
             ("GET", "/showfiles"), ("POST", "/showfiles"):
            return .aria2FileList
        case ("GET", "/aria2_peers"), ("GET", "/api/aria2_peers"),
             ("POST", "/aria2_peers"), ("POST", "/api/aria2_peers"),
             ("GET", "/peers"), ("GET", "/api/peers"),
             ("POST", "/peers"), ("POST", "/api/peers"):
            return .aria2Peers
        case ("POST", "/clear"), ("POST", "/api/clear"):
            return .clear
        case ("POST", "/complete"), ("POST", "/api/complete"),
             ("POST", "/finish"), ("POST", "/api/finish"),
             ("POST", "/done"), ("POST", "/api/done"):
            return .complete
        case ("POST", "/comment"), ("POST", "/api/comment"):
            return .comment
        case ("GET", "/save"), ("GET", "/api/save"),
             ("POST", "/save"), ("POST", "/api/save"):
            return .save
        case ("POST", "/update_cookies"), ("POST", "/api/update_cookies"):
            return .updateCookies
        case ("POST", "/remove"), ("POST", "/api/remove"):
            return .remove
        case ("POST", "/delete"), ("POST", "/api/delete"):
            return .delete
        case ("POST", "/delete_file"), ("POST", "/api/delete_file"):
            return .deleteFile
        default:
            return .notFound
        }
    }

    func isWebUIPath(_ path: String) -> Bool {
        Self.webUIPaths.contains(path.lowercased())
    }

    private func isStaticAssetPath(_ path: String) -> Bool {
        Self.staticAssetPaths.contains(path) || path.hasPrefix("/icon/")
    }

    private static let staticAssetPaths: Set<String> = [
        "/favicon.ico",
        "/loading.gif",
        "/materialize.css",
        "/materialize.js",
        "/jquery.js",
        "/lazysizes.js",
        "/hitomi.css"
    ]

    private static let webUIPaths: Set<String> = [
        "/", "/webui", "/api/webui", "/login", "/api/login",
        "/docs", "/docs.html", "/api/docs", "/about", "/api/about",
        "/help", "/help.html", "/api/help", "/stats", "/api/stats",
        "/statistics", "/api/statistics", "/stat", "/api/stat",
        "/log", "/api/log", "/log/clear", "/api/log/clear",
        "/dirs", "/api/dirs", "/directories", "/api/directories",
        "/finder", "/api/finder", "/analysis", "/api/analysis",
        "/anal", "/api/anal", "/list", "/api/list",
        "/history", "/api/history", "/history/requeue", "/api/history/requeue",
        "/history/enqueue", "/api/history/enqueue", "/history/remove",
        "/api/history/remove", "/history/clear", "/api/history/clear",
        "/search", "/api/search", "/search/providers", "/api/search/providers",
        "/search/enqueue", "/api/search/enqueue", "/clipboard", "/api/clipboard",
        "/clip", "/api/clip", "/clip_viewer", "/clipboard/enqueue",
        "/api/clipboard/enqueue", "/clip/enqueue", "/api/clip/enqueue",
        "/clip_viewer/enqueue", "/clipboard/watch", "/api/clipboard/watch",
        "/clip/watch", "/api/clip/watch", "/clip_viewer/watch",
        "/browser", "/api/browser", "/mybrowser", "/api/mybrowser",
        "/browser/open", "/api/browser/open", "/mybrowser/open",
        "/api/mybrowser/open", "/text", "/api/text", "/text_viewer",
        "/api/text_viewer", "/textviewer", "/api/textviewer", "/text_browser",
        "/api/text_browser", "/textbrowser", "/api/textbrowser",
        "/page_selector", "/api/page_selector", "/page-selector",
        "/api/page-selector", "/select_pages", "/api/select_pages",
        "/select-pages", "/api/select-pages", "/selector", "/api/selector",
        "/pages", "/api/pages", "/view", "/api/view"
    ]
}
