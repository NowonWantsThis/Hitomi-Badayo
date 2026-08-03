import Foundation

struct LocalAPIDocsPageRenderer {
    func page(password: String) -> String {
        let auth = Self.standaloneAuthQuery(password)
        let rowsHTML = Self.rows.map { route, description in
            "<tr><td><code>\(LocalAPIHTMLStyle.escape(route))</code></td><td>\(LocalAPIHTMLStyle.escape(description))</td></tr>"
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo HTTP API Docs</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            main { max-width: 980px; margin: 0 auto; padding: 24px; }
            h1 { font-size: 24px; margin: 0 0 6px; }
            p { color: #5f6368; }
            table { width: 100%; border-collapse: collapse; background: white; border: 1px solid #ddd; }
            th, td { padding: 10px 12px; border-bottom: 1px solid #eee; text-align: left; vertical-align: top; }
            th { background: #fafafa; color: #5f6368; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
            a { color: #1a73e8; }
          </style>
        </head>
        <body>
          <main>
            <h1>Hitomi Badayo HTTP API</h1>
            <p>Loopback API compatible with the original downloader server's common list, view, and queue routes.</p>
            <p><a href="/webui\(auth)">WebUI</a> · <a href="/list\(auth)">List</a> · <a href="/about\(auth)">About</a> · <a href="/help\(auth)">Help</a> · <a href="/stats\(auth)">Stats</a> · <a href="/log\(auth)">Log</a> · <a href="/dirs\(auth)">Dirs</a> · <a href="/finder\(auth)">Finder</a> · <a href="/analysis\(auth)">Analysis</a> · <a href="/history\(auth)">History</a> · <a href="/search\(auth)">Search</a> · <a href="/clipboard\(auth)">Clipboard</a> · <a href="/browser\(auth)">Browser</a> · <a href="/text\(auth)">Text</a> · <a href="/page_selector\(auth)">Pages</a> · <a href="/status\(auth)">Status JSON</a></p>
            <table>
              <thead><tr><th>Route</th><th>Description</th></tr></thead>
              <tbody>
                \(rowsHTML)
              </tbody>
            </table>
          </main>
        </body>
        </html>
        """
    }

    static let rows: [(String, String)] = [
        ("GET /", "Original-compatible HTTP API index with docs, list, and webui links."),
        ("GET /webui?p=0", "Browser control panel for adding URLs and managing the queue, with original-style list page links."),
        ("GET/POST /login", "Original-compatible password login that issues a ticket cookie."),
        ("GET /about", "Original-style About window replacement with version, latest, credits, licenses, and history."),
        ("GET /api/about", "About/version metadata as JSON, including original translation credits."),
        ("GET /help", "Native help text browser replacement with common app and HTTP API entry points."),
        ("GET /api/help", "Help summary and key route links as JSON."),
        ("GET /list?p=0&step=50", "Original-compatible HTML task list with thumbnails, viewer links, PDF, and ZIP actions."),
        ("GET /status", "Queue status and item objects as JSON."),
        ("GET /stats", "Original-style statistics window data as JSON, including queue counts, output totals, runtime speed, elapsed time, and paths."),
        ("GET /log", "Original-style session log page with Auto Refresh & Scroll and Clear controls."),
        ("GET /api/log", "Session log as JSON, including formatted text lines and range/paging aliases."),
        ("POST /log/clear", "Clears the current session log."),
        ("GET /dirs", "Original-style Dirs window replacement listing known queue and history output folders."),
        ("GET /api/dirs", "Known output directories as JSON with queue/history counts, existence, and paging aliases."),
        ("GET /finder?field=artist&q=name&mode=fuzzy", "Original-style Finder replacement for local queue/history artist, group, series, character, and tag metadata."),
        ("GET /api/finder?field=tag&q=maid", "Finder results as JSON with default, regex, and fuzzy matching modes."),
        ("GET /analysis?field=artist", "Original-style metadata analysis tables for artist, group, type, series, character, tag, and language."),
        ("GET /api/analysis?field=language", "Metadata analysis counts as JSON with queue/history totals and search tokens."),
        ("GET /items?start=0&end=9", "Queue item list as JSON, with original-style inclusive range slicing plus offset/limit/count and p/step aliases."),
        ("GET /history?p=0&step=50", "Original-compatible completed download history page with queue-again links and q/search filtering."),
        ("GET /api/history?q=artist", "Completed download history as JSON, with inclusive range slicing plus offset/limit/count and p/step aliases."),
        ("POST /history/requeue", "Requeues history entries by id, ids, index, source/url, or q/search filter."),
        ("POST /history/remove", "Removes history entries by id, ids, index, source/url, or q/search filter."),
        ("POST /history/clear", "Clears completed download history."),
        ("GET /search?q=maid&provider=Hitomi", "Browser searcher page that builds a provider search URL and exposes saved searches."),
        ("GET /api/search?q=maid&provider=Hitomi", "Search provider URL builder as JSON, including provider, bookmark, enqueue, and download links."),
        ("GET /search/providers", "Search providers and saved searches as JSON."),
        ("GET/POST /search/enqueue", "Queues a generated search URL from q/query/search/input and provider/engine/site aliases."),
        ("GET /clipboard", "Original-style clip viewer page for current pasteboard text, candidate URLs, and clipboard watch state."),
        ("GET /api/clipboard", "Clipboard text, candidate URLs, input classifications, and watch state as JSON."),
        ("POST /clipboard/enqueue", "Queues URLs parsed from the current clipboard or supplied text/input body."),
        ("POST /clipboard/watch", "Turns clipboard watch on/off, or toggles it when no state is supplied."),
        ("GET /browser?url=https://example.com", "Original-style mybrowser replacement page for choosing a login URL."),
        ("GET /api/browser?url=https://example.com", "Login browser target URL and cookie status as JSON."),
        ("POST /browser/open", "Opens the native WKWebView login browser for a supplied or inferred HTTP(S) URL."),
        ("GET /text?uid={uid}&index=0", "Original-style text browser page for .txt, .log, .md, .html, .json, .xml, and .csv output files, with task message fallback."),
        ("GET /api/text?uid={uid}&index=0", "Text output as JSON, including filename, byte count, truncation flag, task message, comment, and file links."),
        ("GET /page_selector?uid={uid}", "Original-style page selector replacement for viewing and editing a task's download range."),
        ("GET /api/page_selector?uid={uid}", "Page/file selector state as JSON, including selected pages, compact range, and output-file links when available."),
        ("POST /page_selector?uid={uid}", "Updates an inactive task range from range/pages/selection aliases such as 1-3,5; /selector and /select_pages aliases are accepted."),
        ("GET /item?uid={uid}|index={n}", "Single task JSON, compatible with info metadata and original-style job index lookup."),
        ("GET /names", "Task ids, titles, sources, and statuses as JSON."),
        ("GET/POST /types?input={url}", "Task source hosts/statuses and output media type counts, plus original-style input URL type classification."),
        ("GET /headers", "Current API request and response header hints plus raw headers and original-style items entries as JSON."),
        ("GET /info?uid={uid}", "Single task metadata, file list, chapters, and reader links."),
        ("GET /view?uid={uid}", "HTML file gallery for a completed task."),
        ("GET /viewer?index={n}", "Route alias for /view with original-style job index lookup."),
        ("GET /reader?uid={uid}", "Route alias for /view that keeps the same book, scroll, file, and display option aliases."),
        ("GET /view?uids={uid1},{uid2}", "Multi-task browser view for completed task outputs."),
        ("GET /view?uid={uid}&start_chapter=0&end_chapter=0", "Open a top-level output folder/chapter range."),
        ("GET /view?uid={uid}&mode=book&page=0", "Single-page image reader."),
        ("GET /view?uid={uid}&sort=name&reverse=1", "Sort output display order by path, name, date, size, or type."),
        ("GET/HEAD /file?uid={uid}&index=0", "Serves an output file with Range, ETag, Last-Modified, and 304 support; add download=1 for attachment-style saving."),
        ("GET/HEAD /download_file?uid={uid}&index=0", "Original-style attachment alias for /file."),
        ("GET /thumb?uid={uid}", "Serves the first image thumbnail or a placeholder."),
        ("GET/POST /pdf?uid={uid}", "Creates a PDF from output images, including ZIP/CBZ archives; add download=1 to return the PDF file."),
        ("GET/POST /pdf_converter?uid={uid}", "Original-style alias for PDF creation."),
        ("GET/POST /zip?uid={uid}", "Creates a ZIP or CBZ archive from an output folder; add format=cbz or download=1 as needed."),
        ("GET/POST /archive?uid={uid}", "Original-style archive creation alias for /zip; /cbz is also accepted."),
        ("GET /events", "Server-sent queue status event for browser UI updates."),
        ("GET /ws", "WebSocket queue status snapshot for original-compatible status clients."),
        ("GET/POST /download", "Adds URL input from url, urls, input, JSON body, or raw body text."),
        ("GET/POST /save", "Saves queue and preferences with original-compatible ok/res JSON."),
        ("POST /update_cookies", "Imports raw Cookie text, Netscape cookie text, or JSON cookies arrays into the encrypted cookie store."),
        ("GET/POST /exec_?action=save", "Original-compatible safe command dispatcher for start, stop, save, clear, complete, pdf, zip/archive, comment, remove, delete, pause, resume, aria2_limits, aria2_files, aria2_seed, aria2_file_list, aria2_peers, update_cookies, and add/download."),
        ("GET/POST /exec_?action=pdf&uid={uid}", "Original-compatible command-dispatch PDF creation alias; pdf_converter and create_pdf are accepted."),
        ("GET/POST /exec_?cmd=Zip&uid={uid}", "Original-compatible command-dispatch ZIP/CBZ creation alias; zip, cbz, and archive are accepted."),
        ("POST /start", "Starts the queue."),
        ("POST /stop", "Cancels the active queue run."),
        ("POST /pause?uid={uid}", "Pauses an active aria2c torrent task."),
        ("POST /resume?uid={uid}", "Resumes a paused aria2c torrent task."),
        ("POST /aria2_limits?uid={uid}&down=2M&up=512K", "Applies live aria2c speed limits to an active torrent task."),
        ("POST /aria2_files?uid={uid}&files=1,3-5", "Applies live aria2c torrent file selection to an active task."),
        ("POST /aria2_seed?uid={uid}&seed=30&ratio=1.5", "Applies live aria2c seeding time and ratio to an active torrent task."),
        ("GET/POST /aria2_file_list?uid={uid}", "Lists files inside a queued or active torrent task using aria2c --show-files."),
        ("GET/POST /aria2_peers?uid={uid}", "Lists active aria2c torrent peers through the loopback RPC session."),
        ("POST /clear", "Removes finished, failed, and cancelled tasks from the queue."),
        ("POST /complete?uid={uid}", "Marks inactive task(s) as finished without downloading."),
        ("POST /comment?uid={uid}", "Updates the saved multi-line task comment."),
        ("POST /remove", "Cancels and removes tasks by uid/id/job or original-compatible uids array while preserving downloaded output."),
        ("POST /delete", "Cancels tasks, moves their output to Trash, and removes them by uid/id/job or uids array."),
        ("POST /delete_file?uid={uid}&index=0", "Deletes one output file from an inactive task.")
    ]

    private static func standaloneAuthQuery(_ password: String) -> String {
        guard !password.isEmpty,
              let encoded = password.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
              ) else {
            return ""
        }
        return "?pw=\(encoded)"
    }
}
