import Foundation

struct LocalAPITextPageFileItem {
    var index: Int
    var relativePath: String
}

struct LocalAPITextIndexPageItem {
    var id: UUID
    var title: String
    var source: String
    var message: String
    var hasMessage: Bool
    var files: [LocalAPITextPageFileItem]
}

struct LocalAPITextDetailPageState {
    var id: UUID
    var title: String
    var source: String
    var filename: String
    var selectedFileIndex: Int?
    var text: String
    var bytesRead: Int
    var byteCount: Int
    var isTruncated: Bool
    var message: String
    var comment: String
    var files: [LocalAPITextPageFileItem]
}

struct LocalAPITextPageRenderer {
    func indexPage(
        password: String,
        items: [LocalAPITextIndexPageItem]
    ) -> String {
        let auth = Self.authQuery(password)
        let standaloneAuth = Self.standaloneAuthQuery(password)
        let rows = items.map { item in
            let uid = item.id.uuidString
            let title = Self.escape(
                item.title.isEmpty ? item.source : item.title
            )
            let source = Self.escape(item.source)
            let firstFile = item.files.first
            let href = firstFile.map {
                "/text?uid=\(uid)&index=\($0.index)\(auth)"
            } ?? "/text?uid=\(uid)\(auth)"
            let fileName = firstFile?.relativePath ??
                (item.hasMessage ? "Task Messages" : "No text files")
            let fileList = item.files.prefix(5).map { file in
                let link = "/text?uid=\(uid)&index=\(file.index)\(auth)"
                return #"<a href="\#(Self.escape(link))">\#(Self.escape(file.relativePath))</a>"#
            }.joined(separator: " ")
            let summary = item.files.isEmpty
                ? "message/comment"
                : "\(item.files.count) text file\(item.files.count == 1 ? "" : "s")"
            return """
            <tr>
              <td><a href="\(Self.escape(href))"><strong>\(title)</strong></a><div class="source">\(source)</div></td>
              <td>\(Self.escape(summary))<div class="source">First: \(Self.escape(fileName))</div></td>
              <td class="files">\(fileList.isEmpty ? Self.escape(item.message.trimmingCharacters(in: .whitespacesAndNewlines)) : fileList)</td>
            </tr>
            """
        }.joined(separator: "\n")
        let table = rows.isEmpty
            ? #"<div class="empty">No text output files or task messages.</div>"#
            : """
              <table class="text-index">
                <thead><tr><th>Task</th><th>Text</th><th>Files</th></tr></thead>
                <tbody>\(rows)</tbody>
              </table>
              """

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Text Viewer - Hitomi Badayo</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            header { position: sticky; top: 0; z-index: 2; padding: 12px 14px; background: rgba(255,255,255,.94); border-bottom: 1px solid #ddd; backdrop-filter: blur(10px); }
            h1 { font-size: 18px; margin: 0 0 8px; }
            nav { display: flex; flex-wrap: wrap; gap: 10px; }
            main { max-width: 980px; margin: 0 auto; padding: 18px; }
            table { width: 100%; border-collapse: collapse; background: white; border: 1px solid #ddd; }
            th, td { padding: 10px 12px; border-bottom: 1px solid #eee; text-align: left; vertical-align: top; }
            th { color: #5f6368; background: #fafafa; }
            .source, .files { color: #5f6368; overflow-wrap: anywhere; }
            .files a { display: inline-block; margin: 0 8px 6px 0; }
            .empty { padding: 24px; background: white; border: 1px solid #ddd; color: #6b6f76; text-align: center; }
            a { color: #1a73e8; text-decoration: none; }
          </style>
        </head>
        <body>
          <header>
            <h1>Text Viewer</h1>
            <nav><a href="/webui\(standaloneAuth)">Queue</a><a href="/list\(standaloneAuth)">List</a><a href="/docs\(standaloneAuth)">Docs</a><a href="/api/text\(standaloneAuth)">JSON</a></nav>
          </header>
          <main>
            \(table)
          </main>
        </body>
        </html>
        """
    }

    func detailPage(
        password: String,
        state: LocalAPITextDetailPageState
    ) -> String {
        let auth = Self.authQuery(password)
        let standaloneAuth = Self.standaloneAuthQuery(password)
        let uid = state.id.uuidString
        let title = Self.escape(
            state.title.isEmpty ? state.source : state.title
        )
        let source = Self.escape(state.source)
        let safeFilename = Self.escape(state.filename)
        let fileLink = state.selectedFileIndex.map {
            #"<a href="/file?uid=\#(uid)&index=\#($0)\#(auth)">Raw File</a>"#
        } ?? ""
        let apiLink = state.selectedFileIndex.map {
            "/api/text?uid=\(uid)&index=\($0)\(auth)"
        } ?? "/api/text?uid=\(uid)\(auth)"
        let viewLink = "/view?uid=\(uid)\(auth)"
        let truncatedHTML = state.isTruncated
            ? #"<span class="warn">Truncated at \#(state.bytesRead) bytes.</span>"#
            : ""
        let otherFilesHTML = state.files.map { file in
            let href = "/text?uid=\(uid)&index=\(file.index)\(auth)"
            let active = state.selectedFileIndex == file.index
                ? " active"
                : ""
            return #"<a class="chip\#(active)" href="\#(Self.escape(href))">\#(Self.escape(file.relativePath))</a>"#
        }.joined(separator: "\n")
        let messageHTML = [
            state.message.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
                ? nil
                : "Message: \(state.message.trimmingCharacters(in: .whitespacesAndNewlines))",
            state.comment.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
                ? nil
                : "Comment: \(state.comment.trimmingCharacters(in: .whitespacesAndNewlines))"
        ]
        .compactMap { $0 }
        .map { "<p>\(Self.escape($0))</p>" }
        .joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title) - \(safeFilename)</title>
          <style>
            body { font: 13px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            header { position: sticky; top: 0; z-index: 2; padding: 12px 14px; background: rgba(255,255,255,.94); border-bottom: 1px solid #ddd; backdrop-filter: blur(10px); }
            h1 { font-size: 17px; margin: 0 0 4px; }
            .meta { color: #5f6368; overflow-wrap: anywhere; }
            .toolbar, .chips { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 10px; }
            .toolbar a, .chip { display: inline-flex; min-height: 30px; align-items: center; padding: 0 10px; border: 1px solid #d6d6d6; border-radius: 6px; background: white; text-decoration: none; color: #1a73e8; }
            .chip.active { background: #202124; color: white; border-color: #202124; }
            main { max-width: 1040px; margin: 0 auto; padding: 16px; }
            .message { color: #5f6368; background: white; border: 1px solid #ddd; padding: 10px 12px; margin-bottom: 12px; }
            .text-viewer { box-sizing: border-box; width: 100%; min-height: 58vh; margin: 0; padding: 14px; border: 1px solid #ddd; background: white; color: #202124; overflow: auto; white-space: pre-wrap; overflow-wrap: anywhere; line-height: 1.45; font: 13px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
            .warn { color: #a05a00; }
          </style>
        </head>
        <body>
          <header>
            <h1>\(title)</h1>
            <div class="meta">\(source)</div>
            <div class="meta">\(safeFilename) · \(state.bytesRead) / \(state.byteCount) bytes \(truncatedHTML)</div>
            <div class="toolbar"><a href="/text\(standaloneAuth)">Text Index</a><a href="\(Self.escape(viewLink))">All Files</a>\(fileLink)<a href="\(Self.escape(apiLink))">JSON</a></div>
          </header>
          <main>
            \(otherFilesHTML.isEmpty ? "" : "<div class=\"chips\">\(otherFilesHTML)</div>")
            \(messageHTML.isEmpty ? "" : "<section class=\"message\">\(messageHTML)</section>")
            <pre class="text-viewer">\(Self.escape(state.text))</pre>
          </main>
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
