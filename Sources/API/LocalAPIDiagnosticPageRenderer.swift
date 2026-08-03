import Foundation

struct LocalAPIDiagnosticPageRenderer {
    func logPage(
        password: String,
        logText: String,
        isEmpty: Bool,
        autoRefresh: Bool
    ) -> String {
        let auth = Self.standaloneAuthQuery(password)
        let checked = autoRefresh ? " checked" : ""
        let emptyText = isEmpty
            ? #"<p class="empty">No log entries</p>"#
            : ""
        let passwordField = Self.passwordField(password)

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo Log</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            main { max-width: 1040px; margin: 0 auto; padding: 24px; }
            header { display: flex; gap: 12px; align-items: center; margin-bottom: 14px; }
            h1 { font-size: 24px; margin: 0; }
            .spacer { flex: 1; }
            label { color: #5f6368; display: inline-flex; gap: 6px; align-items: center; }
            button, a.action { font: inherit; border-radius: 6px; border: 1px solid #c8c8c8; padding: 7px 10px; background: white; color: #202124; text-decoration: none; cursor: pointer; }
            textarea { width: 100%; min-height: 62vh; box-sizing: border-box; resize: vertical; border: 1px solid #d7d9dc; border-radius: 6px; padding: 12px; background: white; color: #202124; font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; line-height: 1.45; }
            .empty { color: #6b6f76; }
            nav { margin-top: 12px; display: flex; gap: 12px; }
            nav a { color: #1a73e8; text-decoration: none; }
          </style>
        </head>
        <body>
          <main>
            <header>
              <h1>Log</h1>
              <div class="spacer"></div>
              <label><input id="autoRefresh" type="checkbox"\(checked)> Auto Refresh &amp;&amp; Scroll</label>
              <form action="/log/clear\(auth)" method="post">
                \(passwordField)
                <button type="submit">Clear</button>
              </form>
            </header>
            \(emptyText)
            <textarea id="logText" readonly>\(Self.escape(logText))</textarea>
            <nav>
              <a href="/webui\(auth)">WebUI</a>
              <a href="/docs\(auth)">Docs</a>
              <a href="/api/log\(auth)">JSON</a>
            </nav>
          </main>
          <script>
            const logText = document.getElementById('logText');
            const autoRefresh = document.getElementById('autoRefresh');
            function scrollLog() {
              if (autoRefresh.checked) {
                logText.scrollTop = logText.scrollHeight;
              }
            }
            scrollLog();
            setInterval(function() {
              if (!autoRefresh.checked) return;
              const url = new URL(window.location.href);
              url.searchParams.set('auto', '1');
              window.location.replace(url);
            }, 2000);
          </script>
        </body>
        </html>
        """
    }

    func directoriesPage(
        password: String,
        text: String,
        isEmpty: Bool
    ) -> String {
        let auth = Self.standaloneAuthQuery(password)
        let emptyText = isEmpty
            ? #"<p class="empty">No directories</p>"#
            : ""

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo Dirs</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            main { max-width: 960px; margin: 0 auto; padding: 24px; }
            header { display: flex; gap: 12px; align-items: center; margin-bottom: 14px; }
            h1 { font-size: 24px; margin: 0; }
            .spacer { flex: 1; }
            textarea { width: 100%; min-height: 58vh; box-sizing: border-box; resize: vertical; border: 1px solid #d7d9dc; border-radius: 6px; padding: 12px; background: white; color: #202124; font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; line-height: 1.45; }
            .empty { color: #6b6f76; }
            nav { margin-top: 12px; display: flex; gap: 12px; }
            nav a, header a { color: #1a73e8; text-decoration: none; }
          </style>
        </head>
        <body>
          <main>
            <header>
              <h1>Dirs</h1>
              <div class="spacer"></div>
              <a href="/api/dirs\(auth)">JSON</a>
            </header>
            \(emptyText)
            <textarea readonly>\(Self.escape(text))</textarea>
            <nav>
              <a href="/webui\(auth)">WebUI</a>
              <a href="/docs\(auth)">Docs</a>
              <a href="/list\(auth)">List</a>
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

    private static func escape(_ value: String) -> String {
        LocalAPIHTMLStyle.escape(value)
    }
}
