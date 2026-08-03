import Foundation

struct LocalAPIClipboardPageItem {
    var url: String
    var type: String
    var resolver: String
}

struct LocalAPIInputPageRenderer {
    func browserPage(
        password: String,
        selection: LocalAPIBrowserSelection,
        cookieSummary: String
    ) -> String {
        let auth = Self.standaloneAuthQuery(password)
        let urlString = selection.url?.absoluteString ?? ""
        let passwordField = Self.passwordField(password)
        let resultHTML: String
        if let url = selection.url {
            let safeURL = Self.escape(url.absoluteString)
            resultHTML = """
            <section class="result">
              <div class="label">Login Browser URL</div>
              <a class="url" href="\(safeURL)">\(safeURL)</a>
              <div class="muted">Source: \(Self.escape(selection.source)) · Cookies: \(Self.escape(cookieSummary))</div>
            </section>
            """
        } else {
            resultHTML = #"<section class="result error">No browser URL</section>"#
        }

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo Browser</title>
          <style>
            body { margin: 0; background: #f5f5f3; color: #202124; font: 13px \(LocalAPIHTMLStyle.fontStack); }
            header { display: flex; gap: 10px; align-items: center; padding: 12px 14px; background: white; border-bottom: 1px solid #ddd; position: sticky; top: 0; }
            h1 { font-size: 16px; margin: 0; }
            a { color: #1a73e8; text-decoration: none; }
            main { padding: 14px; max-width: 860px; }
            input, button { font: inherit; min-height: 30px; border: 1px solid #c8ccd1; border-radius: 4px; }
            input { padding: 0 9px; width: 100%; box-sizing: border-box; background: white; }
            button { padding: 0 11px; background: #202124; color: white; cursor: pointer; }
            .browser-panel { display: grid; grid-template-columns: minmax(180px, 1fr) auto; gap: 8px; align-items: center; }
            .result { margin-top: 12px; padding: 12px; background: white; border: 1px solid #ddd; border-radius: 6px; display: grid; gap: 8px; }
            .label, .muted { color: #5f6368; }
            .url { overflow-wrap: anywhere; }
            .error { color: #b3261e; }
            @media (max-width: 640px) {
              header { flex-wrap: wrap; }
              .browser-panel { grid-template-columns: 1fr; }
            }
          </style>
        </head>
        <body>
          <header>
            <h1>Browser</h1>
            <a href="/webui\(auth)">WebUI</a>
            <a href="/list\(auth)">List</a>
            <a href="/clipboard\(auth)">Clipboard</a>
            <a href="/search\(auth)">Search</a>
            <a href="/docs\(auth)">Docs</a>
          </header>
          <main>
            <form class="browser-panel" action="/browser/open\(auth)" method="post">
              \(passwordField)
              <input name="url" value="\(Self.escape(urlString))" autofocus>
              <button type="submit">Open Login Browser</button>
            </form>
            \(resultHTML)
          </main>
        </body>
        </html>
        """
    }

    func clipboardPage(
        password: String,
        inputText: String,
        items: [LocalAPIClipboardPageItem],
        monitorEnabled: Bool
    ) -> String {
        let auth = Self.standaloneAuthQuery(password)
        let passwordField = Self.passwordField(password)
        let watchTitle = monitorEnabled ? "Watch On" : "Watch Off"
        let watchValue = monitorEnabled ? "0" : "1"
        let watchButton = monitorEnabled ? "Turn Watch Off" : "Turn Watch On"
        let rowsHTML = items.enumerated().map { index, item in
            let safeURL = Self.escape(item.url)
            return """
            <tr>
              <td>\(index + 1)</td>
              <td><a class="url" href="\(safeURL)">\(safeURL)</a></td>
              <td>\(Self.escape(item.type))</td>
              <td>\(Self.escape(item.resolver))</td>
            </tr>
            """
        }.joined(separator: "\n")
        let emptyHTML = items.isEmpty
            ? #"<tr><td colspan="4" class="empty">No clipboard URLs</td></tr>"#
            : ""

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo Clipboard</title>
          <style>
            body { margin: 0; background: #f5f5f3; color: #202124; font: 13px \(LocalAPIHTMLStyle.fontStack); }
            header { display: flex; gap: 10px; align-items: center; padding: 12px 14px; background: white; border-bottom: 1px solid #ddd; position: sticky; top: 0; }
            h1 { font-size: 16px; margin: 0; }
            a { color: #1a73e8; text-decoration: none; }
            main { padding: 14px; max-width: 980px; }
            textarea, button { font: inherit; border: 1px solid #c8ccd1; border-radius: 4px; }
            textarea { width: 100%; min-height: 140px; box-sizing: border-box; padding: 9px; resize: vertical; background: white; }
            button { min-height: 30px; padding: 0 11px; background: #202124; color: white; cursor: pointer; }
            button.secondary { background: white; color: #202124; }
            table { width: 100%; border-collapse: collapse; background: white; border: 1px solid #ddd; margin-top: 12px; }
            th, td { padding: 9px 10px; border-bottom: 1px solid #eee; text-align: left; vertical-align: top; }
            th { background: #fafafa; color: #5f6368; }
            .bar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin: 10px 0 14px; }
            .meta { margin-left: auto; color: #5f6368; }
            .url { overflow-wrap: anywhere; }
            .empty { text-align: center; color: #5f6368; padding: 20px; }
            @media (max-width: 640px) {
              header { flex-wrap: wrap; }
              .meta { margin-left: 0; width: 100%; }
            }
          </style>
        </head>
        <body>
          <header>
            <h1>Clipboard</h1>
            <a href="/webui\(auth)">WebUI</a>
            <a href="/list\(auth)">List</a>
            <a href="/search\(auth)">Search</a>
            <a href="/history\(auth)">History</a>
            <a href="/docs\(auth)">Docs</a>
            <span class="meta">\(items.count) URL\(items.count == 1 ? "" : "s") · \(watchTitle)</span>
          </header>
          <main>
            <form class="clipboard-panel" action="/clipboard/enqueue\(auth)" method="post">
              \(passwordField)
              <textarea name="text">\(Self.escape(inputText))</textarea>
              <div class="bar">
                <label><input type="checkbox" name="start" value="1"> Start now</label>
                <button type="submit">Queue Clipboard</button>
              </div>
            </form>
            <form action="/clipboard/watch\(auth)" method="post">
              \(passwordField)
              <input type="hidden" name="enabled" value="\(watchValue)">
              <button class="secondary" type="submit">\(watchButton)</button>
            </form>
            <table class="candidate-list">
              <thead><tr><th>#</th><th>URL</th><th>Type</th><th>Resolver</th></tr></thead>
              <tbody>
                \(rowsHTML)
                \(emptyHTML)
              </tbody>
            </table>
          </main>
        </body>
        </html>
        """
    }

    private static func passwordField(_ password: String) -> String {
        guard !password.isEmpty else { return "" }
        return #"<input type="hidden" name="pw" value="\#(escape(password))">"#
    }

    private static func standaloneAuthQuery(_ password: String) -> String {
        guard !password.isEmpty,
              let encoded = password.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
              ) else {
            return ""
        }
        return "?pw=\(encoded)"
    }

    private static func escape(_ value: String) -> String {
        LocalAPIHTMLStyle.escape(value)
    }
}
