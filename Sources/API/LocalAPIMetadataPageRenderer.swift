import Foundation

struct LocalAPIFinderPageItem {
    var result: MetadataFinderResult
    var searchToken: String
}

struct LocalAPIAnalysisPageItem {
    var entry: MetadataAnalysisEntry
    var searchToken: String
}

@MainActor
struct LocalAPIMetadataPageRenderer {
    func finderPage(
        password: String,
        field: MetadataFinderField,
        mode: MetadataFinderMode,
        query: String,
        items: [LocalAPIFinderPageItem]
    ) -> String {
        let auth = Self.standaloneAuthQuery(password)
        let passwordField = Self.passwordField(password)
        let fieldOptions = MetadataFinderField.allCases.map { option in
            let selected = option == field ? " selected" : ""
            return #"<option value="\#(option.rawValue)"\#(selected)>\#(Self.escape(option.label)) / \#(Self.escape(option.originalLabel))</option>"#
        }.joined(separator: "\n")
        let modeOptions = MetadataFinderMode.allCases.map { option in
            let selected = option == mode ? " selected" : ""
            return #"<option value="\#(option.rawValue)"\#(selected)>\#(Self.escape(option.label))</option>"#
        }.joined(separator: "\n")
        let rows = items.map { item in
            let result = item.result
            let score = result.score.map { "\($0)" } ?? ""
            return """
            <tr>
              <td>\(Self.escape(result.value))</td>
              <td>\(result.totalCount)</td>
              <td>\(result.queueCount)</td>
              <td>\(result.historyCount)</td>
              <td>\(Self.escape(score))</td>
              <td>\(Self.escape(result.sampleTitle))</td>
              <td><code>\(Self.escape(item.searchToken))</code></td>
            </tr>
            """
        }.joined(separator: "\n")
        let empty = items.isEmpty
            ? #"<tr><td colspan="7" class="empty">No matches</td></tr>"#
            : ""
        let jsonAuth = auth.isEmpty
            ? ""
            : "&amp;" + String(auth.dropFirst())

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo Finder</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            main { max-width: 1080px; margin: 0 auto; padding: 24px; }
            h1 { font-size: 24px; margin: 0 0 14px; }
            form { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-bottom: 14px; }
            input, select, button { font: inherit; border-radius: 6px; border: 1px solid #c8c8c8; padding: 8px 10px; background: white; }
            button { background: #202124; color: white; cursor: pointer; }
            table { width: 100%; border-collapse: collapse; background: white; border: 1px solid #ddd; }
            th, td { padding: 9px 10px; border-bottom: 1px solid #eee; text-align: left; vertical-align: top; }
            th { background: #fafafa; color: #5f6368; font-weight: 600; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
            .empty { color: #6b6f76; text-align: center; }
            nav { margin-top: 12px; display: flex; gap: 12px; }
            nav a { color: #1a73e8; text-decoration: none; }
          </style>
        </head>
        <body>
          <main>
            <h1>Finder</h1>
            <form action="/finder" method="get">
              \(passwordField)
              <select name="field">\(fieldOptions)</select>
              <input name="q" value="\(Self.escape(query))" placeholder="Search \(Self.escape(field.label.lowercased()))">
              <select name="mode">\(modeOptions)</select>
              <button type="submit">Search</button>
            </form>
            <table>
              <thead><tr><th>Value</th><th>Total</th><th>Queue</th><th>History</th><th>Score</th><th>Sample</th><th>Token</th></tr></thead>
              <tbody>
                \(rows)
                \(empty)
              </tbody>
            </table>
            <nav>
              <a href="/webui\(auth)">WebUI</a>
              <a href="/docs\(auth)">Docs</a>
              <a href="/api/finder?field=\(field.rawValue)&amp;q=\(Self.queryComponent(query))&amp;mode=\(mode.rawValue)\(jsonAuth)">JSON</a>
            </nav>
          </main>
        </body>
        </html>
        """
    }

    func analysisPage(
        password: String,
        field: MetadataAnalysisField,
        items: [LocalAPIAnalysisPageItem]
    ) -> String {
        let auth = Self.standaloneAuthQuery(password)
        let passwordField = Self.passwordField(password)
        let fieldOptions = MetadataAnalysisField.allCases.map { option in
            let selected = option == field ? " selected" : ""
            return #"<option value="\#(option.rawValue)"\#(selected)>\#(Self.escape(option.label))</option>"#
        }.joined(separator: "\n")
        let rows = items.map { item in
            let entry = item.entry
            return """
            <tr>
              <td>\(Self.escape(entry.value))</td>
              <td>\(entry.totalCount)</td>
              <td>\(entry.queueCount)</td>
              <td>\(entry.historyCount)</td>
              <td>\(Self.escape(entry.sampleTitle))</td>
              <td><code>\(Self.escape(item.searchToken))</code></td>
            </tr>
            """
        }.joined(separator: "\n")
        let empty = items.isEmpty
            ? #"<tr><td colspan="6" class="empty">No metadata</td></tr>"#
            : ""
        let jsonAuth = auth.isEmpty
            ? ""
            : "&amp;" + String(auth.dropFirst())

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo Analysis</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            main { max-width: 1040px; margin: 0 auto; padding: 24px; }
            header { display: flex; gap: 12px; align-items: center; margin-bottom: 14px; }
            h1 { font-size: 24px; margin: 0; }
            .spacer { flex: 1; }
            form { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-bottom: 14px; }
            select, button { font: inherit; border-radius: 6px; border: 1px solid #c8c8c8; padding: 8px 10px; background: white; }
            button { background: #202124; color: white; cursor: pointer; }
            table { width: 100%; border-collapse: collapse; background: white; border: 1px solid #ddd; }
            th, td { padding: 9px 10px; border-bottom: 1px solid #eee; text-align: left; vertical-align: top; }
            th { background: #fafafa; color: #5f6368; font-weight: 600; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
            .empty { color: #6b6f76; text-align: center; }
            nav { margin-top: 12px; display: flex; gap: 12px; }
            nav a, header a { color: #1a73e8; text-decoration: none; }
          </style>
        </head>
        <body>
          <main>
            <header>
              <h1>Analysis</h1>
              <div class="spacer"></div>
              <a href="/api/analysis?field=\(field.rawValue)\(jsonAuth)">JSON</a>
            </header>
            <form action="/analysis" method="get">
              \(passwordField)
              <select name="field">\(fieldOptions)</select>
              <button type="submit">Show</button>
            </form>
            <table>
              <thead><tr><th>Value</th><th>Total</th><th>Queue</th><th>History</th><th>Sample</th><th>Token</th></tr></thead>
              <tbody>
                \(rows)
                \(empty)
              </tbody>
            </table>
            <nav>
              <a href="/webui\(auth)">WebUI</a>
              <a href="/finder\(auth)">Finder</a>
              <a href="/docs\(auth)">Docs</a>
            </nav>
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
