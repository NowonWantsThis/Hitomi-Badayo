import Foundation

struct LocalAPIPageSelectorIndexItem {
    var id: UUID
    var title: String
    var source: String
    var status: String
    var range: String
    var selectedCount: Int
    var totalCount: Int
}

struct LocalAPIPageSelectorCandidateItem {
    var index: Int
    var title: String
    var detail: String
    var isSelected: Bool
    var showsThumbnail: Bool
}

struct LocalAPIPageSelectorJobPageState {
    var id: UUID
    var title: String
    var source: String
    var range: String
    var isActive: Bool
    var selectedCount: Int
    var totalCount: Int
    var candidateCount: Int
    var candidates: [LocalAPIPageSelectorCandidateItem]
}

struct LocalAPIPageSelectorPageRenderer {
    func indexPage(
        password: String,
        items: [LocalAPIPageSelectorIndexItem]
    ) -> String {
        let auth = Self.authQuery(password)
        let standaloneAuth = Self.standaloneAuthQuery(password)
        let rows = items.map { item in
            let uid = item.id.uuidString
            let title = Self.escape(
                item.title.isEmpty ? item.source : item.title
            )
            let href = "/page_selector?uid=\(uid)\(auth)"
            return """
            <tr>
              <td><a href="\(Self.escape(href))"><strong>\(title)</strong></a><div class="source">\(Self.escape(item.source))</div></td>
              <td>\(Self.escape(item.status))</td>
              <td>\(Self.escape(item.range))</td>
              <td>\(item.selectedCount) / \(item.totalCount)</td>
            </tr>
            """
        }.joined(separator: "\n")
        let table = rows.isEmpty
            ? #"<div class="empty">No tasks</div>"#
            : """
              <table class="page-selector-index">
                <thead><tr><th>Task</th><th>Status</th><th>Range</th><th>Selected</th></tr></thead>
                <tbody>\(rows)</tbody>
              </table>
              """

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Page Selector - Hitomi Badayo</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            header { position: sticky; top: 0; z-index: 2; padding: 12px 14px; background: rgba(255,255,255,.94); border-bottom: 1px solid #ddd; backdrop-filter: blur(10px); }
            h1 { font-size: 18px; margin: 0 0 8px; }
            nav { display: flex; flex-wrap: wrap; gap: 10px; }
            main { max-width: 980px; margin: 0 auto; padding: 18px; }
            table { width: 100%; border-collapse: collapse; background: white; border: 1px solid #ddd; }
            th, td { padding: 10px 12px; border-bottom: 1px solid #eee; text-align: left; vertical-align: top; }
            th { color: #5f6368; background: #fafafa; }
            .source { color: #5f6368; overflow-wrap: anywhere; }
            .empty { padding: 24px; background: white; border: 1px solid #ddd; color: #6b6f76; text-align: center; }
            a { color: #1a73e8; text-decoration: none; }
          </style>
        </head>
        <body>
          <header>
            <h1>Page Selector</h1>
            <nav><a href="/webui\(standaloneAuth)">Queue</a><a href="/list\(standaloneAuth)">List</a><a href="/docs\(standaloneAuth)">Docs</a><a href="/api/page_selector\(standaloneAuth)">JSON</a></nav>
          </header>
          <main>
            \(table)
          </main>
        </body>
        </html>
        """
    }

    func jobPage(
        password: String,
        state: LocalAPIPageSelectorJobPageState
    ) -> String {
        let auth = Self.authQuery(password)
        let standaloneAuth = Self.standaloneAuthQuery(password)
        let uid = state.id.uuidString
        let title = Self.escape(
            state.title.isEmpty ? state.source : state.title
        )
        let source = Self.escape(state.source)
        let range = Self.escape(state.range)
        let disabled = state.isActive ? " disabled" : ""
        let rows = state.candidates.map { candidate in
            let checked = candidate.isSelected ? " checked" : ""
            let detail = candidate.detail.isEmpty
                ? ""
                : #"<div class="source">\#(Self.escape(candidate.detail))</div>"#
            let thumbHTML = candidate.showsThumbnail
                ? #"<img src="/thumb?uid=\#(uid)&index=\#(candidate.index)\#(auth)" alt="">"#
                : #"<span class="placeholder">\#(candidate.index + 1)</span>"#
            return """
            <label class="page-row">
              <input type="checkbox" value="\(candidate.index + 1)"\(checked)\(disabled)>
              <span class="thumb">\(thumbHTML)</span>
              <span><strong>[ \(String(format: "%02d", candidate.index + 1)) ] \(Self.escape(candidate.title))</strong>\(detail)</span>
            </label>
            """
        }.joined(separator: "\n")
        let truncated = state.candidateCount > state.candidates.count
            ? #"<p class="muted">Showing \#(state.candidates.count) of \#(state.candidateCount) entries.</p>"#
            : ""

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title) - Page Selector</title>
          <style>
            body { font: 13px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            header { position: sticky; top: 0; z-index: 2; padding: 12px 14px; background: rgba(255,255,255,.94); border-bottom: 1px solid #ddd; backdrop-filter: blur(10px); }
            h1 { font-size: 17px; margin: 0 0 4px; }
            .meta, .source, .muted { color: #5f6368; overflow-wrap: anywhere; }
            .toolbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 10px; }
            .toolbar a, button { display: inline-flex; min-height: 30px; align-items: center; padding: 0 10px; border: 1px solid #d6d6d6; border-radius: 6px; background: white; color: #1a73e8; text-decoration: none; cursor: pointer; font: inherit; }
            button.primary { background: #202124; color: white; border-color: #202124; }
            button:disabled { color: #8a8a8a; cursor: default; }
            main.page-selector { max-width: 960px; margin: 0 auto; padding: 16px; }
            form.range-form { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-bottom: 12px; }
            input[type="text"] { min-width: min(420px, 100%); padding: 8px 10px; border-radius: 6px; border: 1px solid #c8c8c8; font: inherit; }
            .page-list { display: grid; gap: 8px; }
            .page-row { display: grid; grid-template-columns: auto 58px 1fr; gap: 10px; align-items: center; padding: 9px 10px; background: white; border: 1px solid #ddd; }
            .thumb { width: 54px; height: 54px; display: grid; place-items: center; background: #f1f3f4; overflow: hidden; }
            .thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
            .placeholder { color: #6b6f76; font-weight: 600; }
            .empty { padding: 24px; background: white; border: 1px solid #ddd; color: #6b6f76; text-align: center; }
          </style>
        </head>
        <body>
          <header>
            <h1>\(title)</h1>
            <div class="meta">\(source)</div>
            <div class="meta">Range: \(range.isEmpty ? "All" : range) · Selected \(state.selectedCount) / \(state.totalCount)</div>
            <div class="toolbar"><a href="/page_selector\(standaloneAuth)">Page Selector</a><a href="/view?uid=\(uid)\(auth)">View</a><a href="/info?uid=\(uid)\(auth)">Info</a><a href="/api/page_selector?uid=\(uid)\(auth)">JSON</a></div>
          </header>
          <main class="page-selector">
            <form class="range-form" method="post" action="/page_selector">
              <input type="hidden" name="uid" value="\(uid)">
              \(password.isEmpty ? "" : "<input type=\"hidden\" name=\"pw\" value=\"\(Self.escape(password))\">")
              <input id="range" type="text" name="range" value="\(range)" placeholder="1-3,5">
              <button class="primary" type="submit"\(disabled)>Save</button>
              <button type="button" onclick="selectAll()"\(disabled)>All</button>
              <button type="button" onclick="selectNone()"\(disabled)>None</button>
              <button type="button" onclick="rangeFromChecks()"\(disabled)>Use Checks</button>
            </form>
            \(truncated)
            \(state.candidates.isEmpty ? "<div class=\"empty\">No pages</div>" : "<div class=\"page-list\">\(rows)</div>")
          </main>
          <script>
            function checks(){ return Array.from(document.querySelectorAll('.page-row input[type="checkbox"]')); }
            function compact(values){
              values = Array.from(new Set(values.map(Number).filter(v => v > 0))).sort((a,b)=>a-b);
              const ranges = [];
              for (let i = 0; i < values.length; i++) {
                const start = values[i];
                let end = start;
                while (i + 1 < values.length && values[i + 1] === end + 1) end = values[++i];
                ranges.push(start === end ? String(start) : `${start}-${end}`);
              }
              return ranges.join(',');
            }
            function rangeFromChecks(){ document.getElementById('range').value = compact(checks().filter(c => c.checked).map(c => c.value)); }
            function selectAll(){ checks().forEach(c => c.checked = true); rangeFromChecks(); }
            function selectNone(){ checks().forEach(c => c.checked = false); rangeFromChecks(); }
            checks().forEach(c => c.addEventListener('change', rangeFromChecks));
          </script>
        </body>
        </html>
        """
    }

    private static func authQuery(_ password: String) -> String {
        guard let encoded = encodedPassword(password) else { return "" }
        return "&pw=\(encoded)"
    }

    private static func standaloneAuthQuery(_ password: String) -> String {
        guard let encoded = encodedPassword(password) else { return "" }
        return "?pw=\(encoded)"
    }

    private static func encodedPassword(_ password: String) -> String? {
        guard !password.isEmpty else { return nil }
        return password.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        )
    }

    private static func escape(_ value: String) -> String {
        LocalAPIHTMLStyle.escape(value)
    }
}
