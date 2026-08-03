import Foundation

struct LocalAPIHistoryPageItem {
    var index: Int
    var id: UUID
    var source: String
    var title: String
    var outputPath: String
    var completedText: String
    var site: String
}

struct LocalAPIHistoryPageState {
    var items: [LocalAPIHistoryPageItem]
    var visibleCount: Int
    var totalCount: Int
    var step: Int
    var page: Int
    var pageCount: Int
    var query: String
    var showsPaging: Bool
}

struct LocalAPIHistoryPageRenderer {
    func page(
        password: String,
        state: LocalAPIHistoryPageState
    ) -> String {
        let auth = Self.authQuery(password)
        let standaloneAuth = Self.standaloneAuthQuery(password)
        let querySuffix = state.query.isEmpty
            ? ""
            : "&q=\(Self.queryComponent(state.query))"
        let rowsHTML = state.items.map { item in
            let title = Self.escape(
                item.title.isEmpty ? item.source : item.title
            )
            let source = Self.escape(item.source)
            let output = Self.escape(item.outputPath)
            let completed = Self.escape(item.completedText)
            let site = Self.escape(item.site)
            let enqueue = "/download?url=\(Self.queryComponent(item.source))&start=0\(auth)"
            let metadataHTML = site.isEmpty
                ? ""
                : #"<span class="badge">\#(site)</span>"#
            return """
            <tr>
              <td>\(item.index + 1)</td>
              <td><strong>\(title)</strong><div class="muted">\(source)</div><div class="badges">\(metadataHTML)</div></td>
              <td>\(completed)</td>
              <td class="muted">\(output)</td>
              <td>
                <a class="action" href="\(enqueue)">Queue Again</a>
                <form class="inline" action="/history/requeue\(standaloneAuth)" method="post"><input type="hidden" name="id" value="\(item.id.uuidString)"><button type="submit">Requeue</button></form>
                <form class="inline" action="/history/remove\(standaloneAuth)" method="post"><input type="hidden" name="id" value="\(item.id.uuidString)"><button type="submit">Remove</button></form>
              </td>
            </tr>
            """
        }.joined(separator: "\n")
        let emptyHTML = state.items.isEmpty
            ? #"<tr><td colspan="5" class="empty">No history entries</td></tr>"#
            : ""
        let previousPage = max(0, state.page - 1)
        let nextPage = min(state.pageCount - 1, state.page + 1)
        let pagingHTML = state.showsPaging
            ? #"<nav><a class="action" id="prev" href="/history?p=\#(previousPage)&step=\#(state.step)\#(auth)\#(querySuffix)">Previous</a><span>\#(state.page + 1) / \#(state.pageCount)</span><a class="action" id="next" href="/history?p=\#(nextPage)&step=\#(state.step)\#(auth)\#(querySuffix)">Next</a></nav>"#
            : ""
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo History</title>
          <style>
            body { margin: 0; background: #f5f5f3; color: #202124; font: 13px \(LocalAPIHTMLStyle.fontStack); }
            header { display: flex; gap: 10px; align-items: center; padding: 12px 14px; background: white; border-bottom: 1px solid #ddd; position: sticky; top: 0; }
            h1 { font-size: 16px; margin: 0; }
            a { color: #1a73e8; text-decoration: none; }
            button { font: inherit; min-height: 24px; padding: 0 8px; border: 1px solid #d5d8dc; border-radius: 4px; background: #fafafa; color: #1a73e8; cursor: pointer; }
            main { padding: 12px; }
            table { width: 100%; border-collapse: collapse; background: white; border: 1px solid #ddd; }
            th, td { padding: 9px 10px; border-bottom: 1px solid #eee; text-align: left; vertical-align: top; }
            th { background: #fafafa; color: #5f6368; }
            .muted { color: #5f6368; overflow-wrap: anywhere; }
            .summary { margin-left: auto; color: #5f6368; }
            .action { display: inline-flex; align-items: center; min-height: 24px; padding: 0 8px; border: 1px solid #d5d8dc; border-radius: 4px; background: #fafafa; }
            .inline { display: inline; margin-left: 6px; }
            .badges { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 5px; }
            .badge { display: inline-flex; align-items: center; min-height: 20px; padding: 0 7px; border-radius: 999px; background: #eef2ff; color: #3150a3; font-size: 11px; }
            .empty { text-align: center; color: #5f6368; padding: 24px; }
            nav { display: flex; justify-content: center; align-items: center; gap: 14px; padding: 14px 0 4px; }
          </style>
        </head>
        <body>
          <header>
            <h1>History</h1>
            <a href="/webui\(standaloneAuth)">WebUI</a>
            <a href="/list\(standaloneAuth)">List</a>
            <a href="/docs\(standaloneAuth)">Docs</a>
            <form class="inline" action="/history/clear\(standaloneAuth)" method="post"><button type="submit">Clear</button></form>
            <span class="summary">\(state.visibleCount) / \(state.totalCount) entries</span>
          </header>
          <main>
            <table class="history-list">
              <thead><tr><th>#</th><th>Task</th><th>Completed</th><th>Output</th><th>Action</th></tr></thead>
              <tbody>
                \(rowsHTML)
                \(emptyHTML)
              </tbody>
            </table>
            \(pagingHTML)
          </main>
        </body>
        </html>
        """
    }

    private static func authQuery(_ password: String) -> String {
        guard let encodedPassword = encodedPassword(password) else {
            return ""
        }
        return "&pw=\(encodedPassword)"
    }

    private static func standaloneAuthQuery(_ password: String) -> String {
        guard let encodedPassword = encodedPassword(password) else {
            return ""
        }
        return "?pw=\(encodedPassword)"
    }

    private static func encodedPassword(_ password: String) -> String? {
        guard !password.isEmpty else { return nil }
        return password.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        )
    }

    private static func queryComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? value
    }

    private static func escape(_ value: String) -> String {
        LocalAPIHTMLStyle.escape(value)
    }
}
