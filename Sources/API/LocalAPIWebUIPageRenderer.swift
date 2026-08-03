import Foundation

struct LocalAPIWebUIPageRenderer {
    func page(
        passwordQuery: String,
        listURL: String
    ) -> String {
        let password = Self.javascriptStringLiteral(passwordQuery)
        let standaloneAuth = Self.standaloneAuthQuery(passwordQuery)
        let listURLLiteral = Self.javascriptStringLiteral(listURL)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo</title>
          <style>
            :root { color-scheme: light; }
            body { margin: 0; background: #f5f5f3; color: #202124; font: 13px \(LocalAPIHTMLStyle.fontStack); }
            header { position: sticky; top: 0; z-index: 2; display: flex; gap: 8px; align-items: center; padding: 12px 14px; background: rgba(255,255,255,.92); border-bottom: 1px solid #ddd; backdrop-filter: blur(10px); }
            h1 { font-size: 16px; margin: 0 12px 0 0; }
            header a { color: #1a73e8; text-decoration: none; padding: 8px 4px; }
            main { max-width: 1120px; margin: 0 auto; padding: 14px; }
            textarea { width: 100%; min-height: 76px; box-sizing: border-box; resize: vertical; }
            textarea, button, input { font: inherit; border-radius: 6px; border: 1px solid #c8c8c8; padding: 8px 10px; }
            button { background: white; cursor: pointer; }
            button.primary { background: #202124; color: white; border-color: #202124; }
            button.danger { color: #a12424; }
            .tools { display: none; flex-wrap: wrap; gap: 8px; align-items: center; }
            .bar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin: 10px 0 14px; }
            .summary { color: #5f6368; margin-left: auto; }
            .selection-actions { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin: 0 0 14px; }
            .selection-actions span { color: #5f6368; }
            .list-frame { width: 100%; height: min(56vh, 620px); border: 1px solid #ddd; background: white; }
            #homeButton, #refreshButton { min-height: 34px; }
            .toolButton { min-height: 34px; }
            table { width: 100%; border-collapse: collapse; background: white; border: 1px solid #ddd; }
            th, td { padding: 8px 9px; border-bottom: 1px solid #eee; text-align: left; vertical-align: top; }
            th { background: #fafafa; color: #5f6368; font-weight: 600; }
            tr:last-child td { border-bottom: none; }
            .source, .output { color: #5f6368; overflow-wrap: anywhere; font-size: 12px; }
            .status { white-space: nowrap; font-weight: 600; }
            .progress { width: 100%; height: 6px; background: #e8eaed; border-radius: 999px; overflow: hidden; }
            .progress span { display: block; height: 100%; background: #1a73e8; }
            .empty { padding: 24px; text-align: center; color: #6b6f76; background: white; border: 1px solid #ddd; }
          </style>
        </head>
        <body>
          <header>
            <h1>Hitomi Badayo</h1>
            <button id="homeButton" class="waves-effect btn" onclick="home();">Home</button>
            <button id="refreshButton" class="waves-effect btn" onclick="refresh();">Refresh</button>
            <button onclick="command('/start')">Start</button>
            <button onclick="command('/stop')" class="danger">Stop</button>
            <button onclick="command('/clear')">Clear Finished</button>
            <div class="tools" style="display: none;">
              <button class="waves-effect btn-flat toolButton" onclick="remove();">Remove</button>
              <button class="waves-effect btn-flat toolButton danger" onclick="delete_();">Delete</button>
            </div>
            <a href="\(LocalAPIHTMLStyle.escape(listURL))">List</a>
            <a href="/about\(standaloneAuth)">About</a>
            <a href="/help\(standaloneAuth)">Help</a>
            <a href="/clipboard\(standaloneAuth)">Clipboard</a>
            <a href="/browser\(standaloneAuth)">Browser</a>
            <a href="/text\(standaloneAuth)">Text</a>
            <a href="/page_selector\(standaloneAuth)">Pages</a>
            <a href="/stats\(standaloneAuth)">Stats</a>
            <a href="/log\(standaloneAuth)">Log</a>
            <a href="/dirs\(standaloneAuth)">Dirs</a>
            <a href="/finder\(standaloneAuth)">Finder</a>
            <a href="/analysis\(standaloneAuth)">Analysis</a>
            <a href="/search\(standaloneAuth)">Search</a>
            <a href="/history\(standaloneAuth)">History</a>
            <span class="summary" id="summary">Loading...</span>
          </header>
          <main>
            <form id="addForm">
              <textarea id="input" placeholder="Paste one or more URLs"></textarea>
              <div class="bar">
                <label><input type="checkbox" id="startNow" checked> Start now</label>
                <button id="downButton" class="primary" type="submit" onclick="downButton(); return false;">Add URLs</button>
              </div>
            </form>
            <div class="selection-actions">
              <button type="button" onclick="clearSelection()">Clear Selection</button>
              <button type="button" onclick="pauseSelected()">Pause</button>
              <button type="button" onclick="resumeSelected()">Resume</button>
              <span id="selectionCount">0 selected</span>
            </div>
            <iframe src="\(LocalAPIHTMLStyle.escape(listURL))" class="list-frame" onload="onLoad();" title="List"></iframe>
            <div id="content" class="empty" hidden>Loading...</div>
          </main>
          <script>
            const password = \(password);
            const HOME = \(listURLLiteral);
            function apiURL(path) {
              const url = new URL(path, location.origin);
              if (password) url.searchParams.set('pw', password);
              return url;
            }
            async function api(path, options = {}) {
              const response = await fetch(apiURL(path), options);
              if (!response.ok) throw new Error(await response.text());
              return await response.json();
            }
            function escapeText(value) {
              return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
            }
            function renderStatus(data) {
              document.getElementById('summary').textContent = `${data.count} tasks · ${data.running ? 'running' : 'idle'}`;
              render(data.items || []);
            }
            function listFrame() {
              return document.querySelector('.list-frame');
            }
            function home() {
              listFrame().src = HOME;
            }
            function onLoad() {
              updateSelection();
            }
            function updateSelection() {
              const count = selected_uids().length;
              document.getElementById('selectionCount').textContent = `${count} selected`;
              document.querySelectorAll('.tools').forEach(tools => {
                tools.style.display = count ? 'flex' : 'none';
              });
            }
            function clearSelection() {
              const frame = listFrame();
              const doc = frame && frame.contentDocument;
              if (!doc) return;
              doc.querySelectorAll('.item-base.selected').forEach(item => item.classList.remove('selected'));
              updateSelection();
            }
            function selected_uids() {
              const frame = listFrame();
              const doc = frame && frame.contentDocument;
              if (!doc) return [];
              return Array.from(doc.querySelectorAll('.item')).filter(item => item.querySelector('.item-base.selected')).map(item => item.getAttribute('uid')).filter(Boolean);
            }
            function refreshFrame() {
              const frame = listFrame();
              if (frame && frame.contentWindow) frame.contentWindow.location.reload();
            }
            async function refresh() {
              try {
                const data = await api('/status');
                renderStatus(data);
                refreshFrame();
              } catch (error) {
                document.getElementById('content').hidden = false;
                document.getElementById('content').className = 'empty';
                document.getElementById('content').textContent = error.message;
              }
            }
            function render(items) {
              const content = document.getElementById('content');
              if (!items.length) {
                content.hidden = false;
                content.className = 'empty';
                content.textContent = 'No tasks';
                return;
              }
              content.hidden = false;
              content.className = '';
              content.innerHTML = `<table><thead><tr><th>Task</th><th>Status</th><th>Progress</th><th>Output</th><th>Actions</th></tr></thead><tbody>${items.map(item => {
                const pct = Math.max(0, Math.min(100, Math.round((item.progress || 0) * 100)));
                const viewURL = apiURL('/view');
                viewURL.searchParams.set('uid', item.id);
                const infoURL = apiURL('/info');
                infoURL.searchParams.set('uid', item.id);
                const viewLink = item.outputPath ? `<div><a href="${escapeText(viewURL.href)}" target="_blank" rel="noopener">View</a></div>` : '';
                const infoLink = `<div><a href="${escapeText(infoURL.href)}" target="_blank" rel="noopener">Info</a></div>`;
                const pdfButton = item.outputPath ? `<button onclick="taskCommand('/pdf','${escapeText(item.id)}')">PDF</button> ` : '';
                const zipButton = item.outputPath ? `<button onclick="taskCommand('/zip','${escapeText(item.id)}')">ZIP</button> ` : '';
                const canFinish = item.status !== 'Finished' && item.status !== 'Resolving' && (item.status !== 'Downloading' || item.runtimePaused);
                const finishButton = canFinish ? `<button onclick="taskCommand('/complete','${escapeText(item.id)}')">Finish</button> ` : '';
                const canPause = item.runtimeHandler === 'aria2' && item.status === 'Downloading' && !item.runtimePaused;
                const canResume = item.runtimeHandler === 'aria2' && item.status === 'Downloading' && item.runtimePaused;
                const canLimit = item.runtimeHandler === 'aria2' && item.status === 'Downloading' && item.runtimeCanLimit;
                const canSelectFiles = item.runtimeHandler === 'aria2' && item.status === 'Downloading' && item.runtimeCanSelectFiles;
                const canSeed = item.runtimeHandler === 'aria2' && item.status === 'Downloading' && item.runtimeCanSeed;
                const canListFiles = !!item.runtimeCanListFiles;
                const canShowPeers = item.runtimeHandler === 'aria2' && item.status === 'Downloading' && item.runtimeCanShowPeers;
                const pauseButton = canPause ? `<button onclick="taskCommand('/pause','${escapeText(item.id)}')">Pause</button> ` : '';
                const resumeButton = canResume ? `<button onclick="taskCommand('/resume','${escapeText(item.id)}')">Resume</button> ` : '';
                const limitButton = canLimit ? `<button onclick="aria2Limits('${escapeText(item.id)}','${escapeText(item.runtimeMaxDownloadLimit || '')}','${escapeText(item.runtimeMaxUploadLimit || '')}')">Limits</button> ` : '';
                const filesButton = canSelectFiles ? `<button onclick="aria2Files('${escapeText(item.id)}','${escapeText(item.runtimeSelectedFiles || '')}')">Files</button> ` : '';
                const seedButton = canSeed ? `<button onclick="aria2Seed('${escapeText(item.id)}','${escapeText(item.runtimeSeedTimeMinutes || '')}','${escapeText(item.runtimeSeedRatio || '')}')">Seed</button> ` : '';
                const fileListButton = canListFiles ? `<button onclick="aria2FileList('${escapeText(item.id)}')">List</button> ` : '';
                const peersButton = canShowPeers ? `<button onclick="aria2Peers('${escapeText(item.id)}')">Peers</button> ` : '';
                return `<tr>
                  <td><strong>${escapeText(item.title || item.source)}</strong><div class="source">${escapeText(item.source)}</div></td>
                  <td class="status">${escapeText(item.status)}<div class="source">${escapeText(item.message)}</div></td>
                  <td><div class="progress"><span style="width:${pct}%"></span></div><div class="source">${pct}% · ${escapeText(item.completed)}/${escapeText(item.total)}</div></td>
                  <td class="output">${viewLink}${infoLink}${escapeText(item.outputPath)}</td>
                  <td>${pauseButton}${resumeButton}${limitButton}${filesButton}${seedButton}${fileListButton}${peersButton}${pdfButton}${zipButton}${finishButton}<button onclick="taskCommand('/remove','${escapeText(item.id)}')">Remove</button> <button class="danger" onclick="taskCommand('/delete','${escapeText(item.id)}', true)">Delete</button></td>
                </tr>`;
              }).join('')}</tbody></table>`;
            }
            async function command(path) {
              await api(path, { method: 'POST' });
              await refresh();
            }
            async function postUIDCommand(path, uids) {
              if (!uids.length) return;
              await api(path, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({'uids': uids})
              });
              clearSelection();
              await refresh();
            }
            async function remove() {
              await postUIDCommand('/remove', selected_uids());
            }
            async function delete_() {
              await postUIDCommand('/delete', selected_uids());
            }
            async function pauseSelected() {
              await postUIDCommand('/pause', selected_uids());
            }
            async function resumeSelected() {
              await postUIDCommand('/resume', selected_uids());
            }
            async function taskCommand(path, id, confirmDelete = false) {
              if (confirmDelete && !confirm('Delete output files for this task?')) return;
              const body = new URLSearchParams();
              body.set('uid', id);
              await api(path, { method: 'POST', body });
              await refresh();
            }
            async function aria2Limits(id, currentDown, currentUp) {
              const down = prompt('Download limit', currentDown || '');
              if (down === null) return;
              const up = prompt('Upload limit', currentUp || '');
              if (up === null) return;
              const body = new URLSearchParams();
              body.set('uid', id);
              body.set('down', down);
              body.set('up', up);
              await api('/aria2_limits', { method: 'POST', body });
              await refresh();
            }
            async function aria2Files(id, currentFiles) {
              const files = prompt('Torrent files', currentFiles || 'all');
              if (files === null) return;
              const body = new URLSearchParams();
              body.set('uid', id);
              body.set('files', files);
              await api('/aria2_files', { method: 'POST', body });
              await refresh();
            }
            async function aria2Seed(id, currentSeed, currentRatio) {
              const seed = prompt('Seed time minutes', currentSeed || '0');
              if (seed === null) return;
              const ratio = prompt('Seed ratio', currentRatio || '');
              if (ratio === null) return;
              const body = new URLSearchParams();
              body.set('uid', id);
              body.set('seed', seed);
              body.set('ratio', ratio);
              await api('/aria2_seed', { method: 'POST', body });
              await refresh();
            }
            async function aria2FileList(id) {
              const body = new URLSearchParams();
              body.set('uid', id);
              const data = await api('/aria2_file_list', { method: 'POST', body });
              const files = data.files || [];
              const text = files.length ? files.map(file => file.summary || `${file.index}: ${file.path}`).join('\\n') : 'No torrent files';
              alert(text);
              await refresh();
            }
            async function aria2Peers(id) {
              const body = new URLSearchParams();
              body.set('uid', id);
              const data = await api('/aria2_peers', { method: 'POST', body });
              const peers = data.peers || [];
              const text = peers.length ? peers.map(peer => peer.summary || `${peer.ip}:${peer.port}`).join('\\n') : 'No peers';
              alert(text);
              await refresh();
            }
            async function downButton() {
              const input = document.getElementById('input');
              input.focus();
              if (!input.value.trim()) return;
              await api('/download', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({'input': input.value, 'start': document.getElementById('startNow').checked ? '1' : '0'})
              });
              input.value = '';
              await refresh();
            }
            document.getElementById('addForm').addEventListener('submit', async event => {
              event.preventDefault();
              await downButton();
            });
            function connectEvents() {
              if (!window.EventSource) return false;
              const source = new EventSource(apiURL('/events').href);
              source.addEventListener('status', event => {
                try {
                  renderStatus(JSON.parse(event.data));
                } catch {
                  refresh();
                }
              });
              source.onerror = function() {};
              return true;
            }
            refresh();
            if (!connectEvents()) setInterval(refresh, 3000);
          </script>
        </body>
        </html>
        """
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

    private static func javascriptStringLiteral(_ value: String) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: [value],
            options: []
        )) ?? Data(#"[""]"#.utf8)
        let encoded = String(data: data, encoding: .utf8) ?? #"[""]"#
        return String(encoded.dropFirst().dropLast())
    }
}
