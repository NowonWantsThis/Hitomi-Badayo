import Foundation

struct LocalAPICorePageRenderer {
    func loginPage() -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo HTTP API</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            main { max-width: 420px; margin: 18vh auto 0; padding: 24px; }
            input, button { font: inherit; border-radius: 6px; border: 1px solid #c8c8c8; padding: 9px 11px; }
            input { width: calc(100% - 24px); background: white; }
            button { margin-top: 10px; background: #202124; color: white; cursor: pointer; }
            p { color: #6b6f76; }
          </style>
        </head>
        <body>
          <main>
            <h1>Hitomi Badayo HTTP API</h1>
            <p>Password is required.</p>
            <form action="/webui" method="get">
              <input type="password" name="pw" placeholder="Password" autofocus>
              <button type="submit">Open</button>
            </form>
          </main>
        </body>
        </html>
        """
    }

    func aboutPage(
        password: String,
        about: AppAboutInfo
    ) -> String {
        let auth = Self.standaloneAuthQuery(password)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>About Hitomi Badayo</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            main { max-width: 760px; margin: 0 auto; padding: 28px 24px; }
            header { display: flex; gap: 16px; align-items: center; margin-bottom: 18px; }
            .logo { width: 64px; height: 64px; border-radius: 14px; display: grid; place-items: center; background: #202124; color: white; font-size: 30px; font-weight: 700; }
            h1 { font-size: 26px; margin: 0 0 4px; }
            h2 { font-size: 16px; margin: 22px 0 8px; }
            p { color: #5f6368; line-height: 1.5; }
            .version { font-weight: 700; color: #202124; }
            .panel { background: white; border: 1px solid #ddd; border-radius: 8px; padding: 14px 16px; margin-top: 12px; }
            ul { margin: 8px 0 0 18px; padding: 0; color: #3c4043; line-height: 1.55; }
            nav { margin-top: 18px; display: flex; gap: 12px; flex-wrap: wrap; }
            a { color: #1a73e8; text-decoration: none; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
          </style>
        </head>
        <body>
          <main>
            <header>
              <div class="logo">H</div>
              <div>
                <h1>\(Self.escape(about.displayName))</h1>
                <div class="version">Current: \(Self.escape(about.currentVersionText))</div>
                <div>Latest: \(Self.escape(about.latestVersionText))</div>
              </div>
            </header>
            <section class="panel">
              <p>\(Self.escape(about.developedBy))</p>
              <p><code>\(Self.escape(about.architecture))</code> · macOS \(Self.escape(about.minimumSystemVersion))+ · \(Self.escape(about.operatingSystemVersion))</p>
            </section>
            <section id="licenses" class="panel">
              <h2>Licenses</h2>
              <p>\(Self.escape(about.licenseSummary))</p>
            </section>
            <section id="history" class="panel">
              <h2>History</h2>
              <p>\(Self.escape(about.historySummary))</p>
            </section>
            <nav>
              <a href="/help\(auth)">Help</a>
              <a href="/docs\(auth)">Docs</a>
              <a href="/webui\(auth)">WebUI</a>
              <a href="/api/about\(auth)">JSON</a>
            </nav>
          </main>
        </body>
        </html>
        """
    }

    func helpPage(password: String) -> String {
        let auth = Self.standaloneAuthQuery(password)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo Help</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            main { max-width: 820px; margin: 0 auto; padding: 28px 24px; }
            h1 { font-size: 26px; margin: 0 0 8px; }
            h2 { font-size: 17px; margin: 22px 0 8px; }
            p, li { color: #4f5358; line-height: 1.55; }
            section { background: white; border: 1px solid #ddd; border-radius: 8px; padding: 14px 16px; margin-top: 12px; }
            nav { margin-top: 18px; display: flex; gap: 12px; flex-wrap: wrap; }
            a { color: #1a73e8; text-decoration: none; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
          </style>
        </head>
        <body>
          <main>
            <h1>Help</h1>
            <p>Native macOS help for queueing, downloading, and managing media.</p>
            <section>
              <h2>Add URLs</h2>
              <ul>
                <li>Paste URLs into the main input and use Add or Start Queue.</li>
                <li>Empty Add can read supported URLs from the clipboard.</li>
                <li>Task rows expose Info, Edit, Comment, Retry, PDF, ZIP/CBZ, Move, Delete, and browser viewing actions.</li>
              </ul>
            </section>
            <section>
              <h2>Original-Style Helper Windows</h2>
              <p>Use Log, Dirs, Finder, Analysis, History, Search, Clipboard, Browser, Text, and Pages from the toolbar, app menu, or local WebUI.</p>
            </section>
            <section>
              <h2>HTTP API</h2>
              <p>Enable the local HTTP API to use <code>/webui</code>, <code>/docs</code>, <code>/about</code>, <code>/help</code>, and JSON routes such as <code>/api/about</code> and <code>/api/help</code>.</p>
            </section>
            <nav>
              <a href="/about\(auth)">About</a>
              <a href="/docs\(auth)">Docs</a>
              <a href="/webui\(auth)">WebUI</a>
              <a href="/api/help\(auth)">JSON</a>
            </nav>
          </main>
        </body>
        </html>
        """
    }

    func indexPage(
        password: String,
        apiEnabled: Bool,
        dateText: String
    ) -> String {
        let standaloneAuth = Self.standaloneAuthQuery(password)
        let auth = Self.authQuery(password)
        let rows: [(String, String)] = [
            ("Docs", "/docs\(standaloneAuth)"),
            ("List", "/list?p=0\(auth)"),
            ("List without paging", "/list\(standaloneAuth)"),
            ("About", "/about\(standaloneAuth)"),
            ("Help", "/help\(standaloneAuth)"),
            ("Stats", "/stats\(standaloneAuth)"),
            ("Log", "/log\(standaloneAuth)"),
            ("Dirs", "/dirs\(standaloneAuth)"),
            ("Finder", "/finder\(standaloneAuth)"),
            ("Analysis", "/analysis\(standaloneAuth)"),
            ("History", "/history\(standaloneAuth)"),
            ("Search", "/search\(standaloneAuth)"),
            ("Clipboard", "/clipboard\(standaloneAuth)"),
            ("Browser", "/browser\(standaloneAuth)"),
            ("Text", "/text\(standaloneAuth)"),
            ("Pages", "/page_selector\(standaloneAuth)"),
            ("WebUI", "/webui?p=0\(auth)")
        ]
        let linksHTML = rows.map { label, href in
            #"<p><a href="\#(Self.escape(href))">\#(Self.escape(label))</a></p>"#
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo HTTP API</title>
          <style>
            body { font: 14px \(LocalAPIHTMLStyle.fontStack); margin: 0; background: #f7f7f5; color: #202124; }
            main { max-width: 520px; margin: 0 auto; padding: 24px; }
            h1 { font-size: 24px; margin: 0 0 12px; }
            p { margin: 8px 0; color: #5f6368; }
            a { color: #1a73e8; text-decoration: none; }
          </style>
        </head>
        <body>
          <main>
            <h1>Hitomi Badayo HTTP API</h1>
            <p>Enabled: \(apiEnabled ? "true" : "false")</p>
            <p>Time: \(dateText)</p>
            \(linksHTML)
          </main>
        </body>
        </html>
        """
    }

    private static func escape(_ value: String) -> String {
        LocalAPIHTMLStyle.escape(value)
    }

    private static func standaloneAuthQuery(_ password: String) -> String {
        encodedPassword(password).map { "?pw=\($0)" } ?? ""
    }

    private static func authQuery(_ password: String) -> String {
        encodedPassword(password).map { "&pw=\($0)" } ?? ""
    }

    private static func encodedPassword(_ password: String) -> String? {
        guard !password.isEmpty else { return nil }
        return password.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        )
    }
}
