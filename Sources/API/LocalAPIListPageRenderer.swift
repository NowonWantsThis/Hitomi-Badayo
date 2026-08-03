import Foundation

struct LocalAPIListPageItem {
    var index: Int
    var id: UUID
    var status: String
    var progress: Int
    var completed: Int
    var total: Int
    var title: String
    var source: String
    var message: String
    var comment: String
    var outputPath: String
    var badges: [String]
    var canCreatePDF: Bool
    var canCreateZIP: Bool
}

struct LocalAPIListPageState {
    var items: [LocalAPIListPageItem]
    var totalCount: Int
    var usesRange: Bool
    var usesPaging: Bool
    var requestedPage: Int
    var step: Int
    var singleMode: Bool
}

struct LocalAPIListPageRenderer {
    func page(
        password: String,
        state: LocalAPIListPageState
    ) -> String {
        let auth = Self.authQuery(password)
        let standaloneAuth = Self.standaloneAuthQuery(password)
        let viewMode = state.singleMode ? "&mode=book&page=0" : ""
        let itemsHTML = state.items.map { item in
            let uid = item.id.uuidString
            let statusClass = item.status.lowercased()
            let title = Self.escape(
                item.title.isEmpty ? item.source : item.title
            )
            let source = Self.escape(item.source)
            let message = Self.escape(item.message)
            let comment = Self.escape(item.comment)
            let commentHTML = comment.isEmpty
                ? ""
                : #"<div class="comment">\#(comment)</div>"#
            let output = Self.escape(item.outputPath)
            let badgesHTML = item.badges.isEmpty
                ? ""
                : #"<div class="badges">\#(item.badges.prefix(8).map { "<span class=\"badge\">\(Self.escape($0))</span>" }.joined())</div>"#
            let thumb = "/thumb?uid=\(uid)\(auth)"
            let view = "/view?uid=\(uid)\(auth)\(viewMode)"
            let pdf = "/pdf?uid=\(uid)\(auth)"
            let zip = "/zip?uid=\(uid)\(auth)"
            let pdfHTML = item.canCreatePDF
                ? #"<a class="action" href="\#(pdf)">PDF</a>"#
                : ""
            let zipHTML = item.canCreateZIP
                ? #"<a class="action" href="\#(zip)">ZIP</a>"#
                : ""
            return """
            <li class="item \(statusClass)" uid="\(uid)" data-index="\(item.index)">
              <div class="item-base">
                <a class="thumb" href="\(view)"><img src="\(thumb)" alt=""></a>
                <div class="body">
                  <a class="title" href="\(view)">\(title)</a>
                  <div class="actions"><a class="action" href="\(view)">View</a>\(pdfHTML)\(zipHTML)</div>
                  <div class="source">\(source)</div>
                  <div class="meta"><span>\(Self.escape(item.status))</span><span>\(item.completed)/\(item.total)</span><span>\(item.progress)%</span></div>
                  \(badgesHTML)
                  <div class="progress"><span style="width:\(item.progress)%"></span></div>
                  <div class="message">\(message)</div>
                  \(commentHTML)
                  <div class="output">\(output)</div>
                </div>
              </div>
            </li>
            """
        }.joined(separator: "\n")

        let pageCount = state.usesPaging
            ? max(
                1,
                Int(
                    ceil(
                        Double(state.totalCount) / Double(state.step)
                    )
                )
            )
            : 1
        var paging = ""
        if state.usesPaging {
            let lowerPage = max(0, state.requestedPage - 4)
            let upperPage = min(pageCount - 1, state.requestedPage + 4)
            let pageLinks = (lowerPage...upperPage).map { page -> String in
                let href = "/list?p=\(page)&step=\(state.step)\(auth)"
                let idAttribute: String
                if page == state.requestedPage - 1 {
                    idAttribute = #" id="prev""#
                } else if page == state.requestedPage + 1 {
                    idAttribute = #" id="next""#
                } else {
                    idAttribute = ""
                }
                let activeClass = page == state.requestedPage
                    ? " active"
                    : ""
                return #"<a\#(idAttribute) class="paging-item\#(activeClass)" href="\#(href)">\#(page + 1)</a>"#
            }.joined(separator: "")
            let previousFallback = state.requestedPage == 0
                ? #"<span id="prev" class="paging-item disabled">‹</span>"#
                : ""
            let nextFallback = state.requestedPage + 1 >= pageCount
                ? #"<span id="next" class="paging-item disabled">›</span>"#
                : ""
            paging = #"<nav class="paging">\#(previousFallback)\#(pageLinks)\#(nextFallback)</nav>"#
        }

        let emptyHTML = state.items.isEmpty
            ? #"<li class="empty">No tasks</li>"#
            : ""
        let useRange = state.usesRange
        let visible = state.items
        let total = state.totalCount
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hitomi Badayo List</title>
          <style>
            body { margin: 0; background: #f5f5f3; color: #202124; font: 13px \(LocalAPIHTMLStyle.fontStack); }
            header { display: flex; gap: 10px; align-items: center; padding: 12px 14px; background: white; border-bottom: 1px solid #ddd; position: sticky; top: 0; }
            h1 { font-size: 16px; margin: 0; }
            a { color: #1a73e8; text-decoration: none; }
            .summary { margin-left: auto; color: #5f6368; }
            ul { list-style: none; margin: 0; padding: 12px; display: grid; gap: 8px; }
            .item { background: white; border: 1px solid #ddd; border-radius: 6px; overflow: hidden; }
            .item-base { display: grid; grid-template-columns: 96px minmax(0, 1fr); gap: 12px; padding: 10px; cursor: default; }
            .item-base.selected { background: #dfe9ff; }
            .thumb { width: 96px; height: 64px; background: #eef0f2; border-radius: 4px; overflow: hidden; display: block; }
            .thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
            .title { font-weight: 700; color: #202124; overflow-wrap: anywhere; }
            .actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 5px; }
            .action { display: inline-flex; align-items: center; min-height: 22px; padding: 0 8px; border: 1px solid #d5d8dc; border-radius: 4px; background: #fafafa; color: #1a73e8; font-size: 12px; }
            .source, .message, .comment, .output { color: #5f6368; overflow-wrap: anywhere; font-size: 12px; margin-top: 3px; }
            .comment { color: #3f5f9f; white-space: pre-wrap; }
            .meta { display: flex; flex-wrap: wrap; gap: 8px; color: #5f6368; margin-top: 6px; }
            .badges { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
            .badge { display: inline-flex; align-items: center; min-height: 20px; padding: 0 7px; border-radius: 999px; background: #eef2ff; color: #3150a3; font-size: 11px; max-width: 100%; overflow-wrap: anywhere; }
            .progress { width: 100%; height: 6px; background: #e8eaed; border-radius: 999px; overflow: hidden; margin-top: 6px; }
            .progress span { display: block; height: 100%; background: #1a73e8; }
            .empty { padding: 24px; text-align: center; color: #5f6368; background: white; border: 1px solid #ddd; border-radius: 6px; }
            .paging { display: flex; justify-content: center; align-items: center; gap: 14px; padding: 12px 0 20px; }
            .paging-item { display: inline-flex; align-items: center; justify-content: center; min-width: 28px; min-height: 28px; padding: 0 8px; border: 1px solid #d5d8dc; border-radius: 4px; background: white; color: #1a73e8; }
            .paging-item.active { background: #202124; color: white; border-color: #202124; }
            .disabled { color: #9aa0a6; }
            .item-base { position: relative; transition: transform .12s ease, background .12s ease; }
            .item-base.right-swiping { box-shadow: 0 8px 18px rgba(0,0,0,.12); }
            .item-base.swipe-delete-ready { background: #ffe6e6; }
            .item-base.swipe-delete-ready::after { content: "Delete"; position: absolute; right: 12px; top: 50%; transform: translateY(-50%); color: #b3261e; font-weight: 700; }
          </style>
        </head>
        <body>
          <header>
            <h1>Hitomi Badayo</h1>
            <a href="/webui\(standaloneAuth)">WebUI</a>
            <a href="/docs\(standaloneAuth)">Docs</a>
            <span class="summary">\(useRange ? "\(visible.count) / \(total) tasks" : "\(total) tasks")</span>
          </header>
          <ul class="listWidget">
            \(itemsHTML)
            \(emptyHTML)
          </ul>
          \(paging)
          <script>
            const deleteURL = \(Self.javascriptStringLiteral("/delete\(standaloneAuth)"));
            document.addEventListener("keydown", function(event) {
              if (event.ctrlKey || event.altKey || event.shiftKey) return;
              if (event.key === "ArrowLeft") document.getElementById("prev")?.click();
              if (event.key === "ArrowRight") document.getElementById("next")?.click();
            });
            var isMouseDown = false;
            var isSelected = false;
            var rightSwipeState = null;
            var rightSwipeThreshold = 90;
            async function deleteSwipedItem(item) {
              var uid = item && item.getAttribute("uid");
              if (!uid) return;
              if (!confirm("Delete output files for this task?")) return;
              var body = new URLSearchParams();
              body.set("uid", uid);
              var response = await fetch(deleteURL, { method: "POST", body: body });
              if (response.ok) {
                location.reload();
              } else {
                alert(await response.text());
              }
            }
            function resetRightSwipe() {
              if (!rightSwipeState) return;
              var itemBase = rightSwipeState.itemBase;
              itemBase.style.transform = "";
              itemBase.classList.remove("right-swiping", "swipe-delete-ready");
              rightSwipeState = null;
            }
            function beginRightSwipe(event, itemBase) {
              rightSwipeState = {
                itemBase: itemBase,
                item: itemBase.closest(".item"),
                startX: event.clientX,
                ready: false
              };
              itemBase.classList.add("right-swiping");
              event.preventDefault();
            }
            document.querySelectorAll(".item-base").forEach(function(itemBase) {
              itemBase.addEventListener("mousedown", function(event) {
                if (event.target.closest("a, button, input, textarea, select")) return;
                if (event.button === 2) {
                  beginRightSwipe(event, itemBase);
                  return;
                }
                if (event.button !== 0) return;
                isMouseDown = true;
                itemBase.classList.toggle("selected");
                isSelected = itemBase.classList.contains("selected");
                if (window.parent && typeof window.parent.updateSelection === "function") {
                  window.parent.updateSelection();
                }
                event.preventDefault();
              });
              itemBase.addEventListener("mouseover", function(event) {
                if (!isMouseDown || event.target.closest("a, button, input, textarea, select")) return;
                itemBase.classList.toggle("selected", isSelected);
                if (window.parent && typeof window.parent.updateSelection === "function") {
                  window.parent.updateSelection();
                }
              });
            });
            document.addEventListener("mousemove", function(event) {
              if (!rightSwipeState) return;
              var delta = Math.min(0, event.clientX - rightSwipeState.startX);
              var clamped = Math.max(delta, -128);
              rightSwipeState.itemBase.style.transform = "translateX(" + clamped + "px)";
              rightSwipeState.ready = delta <= -rightSwipeThreshold;
              rightSwipeState.itemBase.classList.toggle("swipe-delete-ready", rightSwipeState.ready);
              event.preventDefault();
            });
            document.addEventListener("contextmenu", function(event) {
              if (event.target.closest(".item-base")) {
                event.preventDefault();
              }
            });
            document.addEventListener("mouseup", function() {
              isMouseDown = false;
              if (rightSwipeState) {
                var state = rightSwipeState;
                var shouldDelete = state.ready;
                resetRightSwipe();
                if (shouldDelete) {
                  deleteSwipedItem(state.item);
                }
              }
            });
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

    private static func javascriptStringLiteral(_ value: String) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: [value],
            options: []
        )) ?? Data(#"[""]"#.utf8)
        let encoded = String(data: data, encoding: .utf8) ?? #"[""]"#
        return String(encoded.dropFirst().dropLast())
    }

    private static func escape(_ value: String) -> String {
        LocalAPIHTMLStyle.escape(value)
    }
}
