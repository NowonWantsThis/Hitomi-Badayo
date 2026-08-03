import Foundation

struct LocalAPISearchBookmarkPageItem {
    var title: String
    var providerName: String
    var query: String
    var url: URL?
}

struct LocalAPISearchPageRenderer {
    func page(
        password: String,
        build: LocalAPISearchBuild,
        providers: [SearchProvider],
        selectedProviderID: UUID?,
        bookmarks: [LocalAPISearchBookmarkPageItem]
    ) -> String {
        let auth = Self.standaloneAuthQuery(password)
        let queryValue = Self.escape(build.query)
        let passwordField = Self.passwordField(password)
        let providerOptions = providers.map { provider in
            let selected = provider.id == selectedProviderID ? " selected" : ""
            return #"<option value="\#(Self.escape(provider.name))"\#(selected)>\#(Self.escape(provider.name))</option>"#
        }.joined(separator: "\n")

        let resultHTML: String
        if build.providerMissing {
            resultHTML = #"<section class="result error">Search provider not found: \#(Self.escape(build.providerKey))</section>"#
        } else if let url = build.url, let provider = build.provider {
            let urlString = Self.escape(url.absoluteString)
            resultHTML = """
            <section class="result">
              <div class="label">Generated URL</div>
              <a class="url" href="\(urlString)">\(urlString)</a>
              <form action="/search/enqueue\(auth)" method="post">
                <input type="hidden" name="provider" value="\(Self.escape(provider.name))">
                <input type="hidden" name="q" value="\(queryValue)">
                <input type="hidden" name="start" value="0">
                <button type="submit">Queue Search</button>
              </form>
            </section>
            """
        } else if build.query.isEmpty {
            resultHTML = #"<section class="result muted">No search query</section>"#
        } else {
            resultHTML = #"<section class="result error">Search URL could not be built</section>"#
        }

        let bookmarkRows = bookmarks.map { bookmark in
            let title = Self.escape(bookmark.title)
            let query = Self.escape(bookmark.query)
            let provider = Self.escape(bookmark.providerName)
            let link = bookmark.url.map {
                #"<a class="url" href="\#(Self.escape($0.absoluteString))">\#(Self.escape($0.absoluteString))</a>"#
            } ?? #"<span class="muted">Unavailable</span>"#
            return """
            <tr>
              <td><strong>\(title)</strong><div class="muted">\(provider) · \(query)</div></td>
              <td>\(link)</td>
              <td>
                <form action="/search/enqueue\(auth)" method="post">
                  <input type="hidden" name="provider" value="\(provider)">
                  <input type="hidden" name="q" value="\(query)">
                  <input type="hidden" name="start" value="0">
                  <button type="submit">Queue</button>
                </form>
              </td>
            </tr>
            """
        }.joined(separator: "\n")
        let emptyBookmarks = bookmarks.isEmpty
            ? #"<tr><td colspan="3" class="empty">No saved searches</td></tr>"#
            : ""
        let providerRows = providers.map { provider in
            """
            <tr>
              <td>\(Self.escape(provider.name))</td>
              <td><code>\(Self.escape(provider.urlTemplate))</code></td>
            </tr>
            """
        }.joined(separator: "\n")
        let emptyProviders = providers.isEmpty
            ? #"<tr><td colspan="2" class="empty">No search providers</td></tr>"#
            : ""

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo Search</title>
          <style>
            body { margin: 0; background: #f5f5f3; color: #202124; font: 13px \(LocalAPIHTMLStyle.fontStack); }
            header { display: flex; gap: 10px; align-items: center; padding: 12px 14px; background: white; border-bottom: 1px solid #ddd; position: sticky; top: 0; }
            h1 { font-size: 16px; margin: 0; }
            h2 { font-size: 14px; margin: 22px 0 8px; }
            a { color: #1a73e8; text-decoration: none; }
            main { padding: 14px; max-width: 980px; }
            input, select, button { font: inherit; min-height: 30px; border: 1px solid #c8ccd1; border-radius: 4px; background: white; }
            input, select { padding: 0 9px; }
            button { padding: 0 11px; background: #202124; color: white; cursor: pointer; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; overflow-wrap: anywhere; }
            table { width: 100%; border-collapse: collapse; background: white; border: 1px solid #ddd; }
            th, td { padding: 9px 10px; border-bottom: 1px solid #eee; text-align: left; vertical-align: top; }
            th { background: #fafafa; color: #5f6368; }
            .search-panel { display: grid; grid-template-columns: minmax(130px, 190px) minmax(180px, 1fr) auto; gap: 8px; align-items: center; }
            .result { margin-top: 12px; padding: 12px; background: white; border: 1px solid #ddd; border-radius: 6px; display: grid; gap: 8px; }
            .label, .muted { color: #5f6368; }
            .error { color: #b3261e; }
            .url { overflow-wrap: anywhere; }
            .empty { text-align: center; color: #5f6368; padding: 20px; }
            @media (max-width: 640px) {
              header { flex-wrap: wrap; }
              .search-panel { grid-template-columns: 1fr; }
            }
          </style>
        </head>
        <body>
          <header>
            <h1>Search</h1>
            <a href="/webui\(auth)">WebUI</a>
            <a href="/list\(auth)">List</a>
            <a href="/history\(auth)">History</a>
            <a href="/docs\(auth)">Docs</a>
          </header>
          <main>
            <form class="search-panel" action="/search" method="get">
              \(passwordField)
              <select name="provider">\(providerOptions)</select>
              <input type="search" name="q" value="\(queryValue)" autofocus>
              <button type="submit">Search</button>
            </form>
            \(resultHTML)
            <h2>Saved Searches</h2>
            <table class="bookmark-list">
              <thead><tr><th>Search</th><th>URL</th><th>Action</th></tr></thead>
              <tbody>
                \(bookmarkRows)
                \(emptyBookmarks)
              </tbody>
            </table>
            <h2>Providers</h2>
            <table class="provider-list">
              <thead><tr><th>Name</th><th>Template</th></tr></thead>
              <tbody>
                \(providerRows)
                \(emptyProviders)
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
