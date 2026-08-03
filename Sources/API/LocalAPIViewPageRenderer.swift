import Foundation

struct LocalAPIViewFileItem {
    var originalIndex: Int
    var relativePath: String
    var mediaType: String
}

struct LocalAPIMultiViewTaskItem {
    var id: UUID
    var title: String
    var source: String
    var files: [LocalAPIViewFileItem]
}

struct LocalAPIViewChapterItem {
    var title: String
    var indexes: [Int]
}

struct LocalAPIScrollViewImageItem {
    var position: Int
    var originalIndex: Int
    var relativePath: String
}

struct LocalAPIViewPageRenderer {
    func overviewPage(
        id: UUID,
        title: String,
        source: String,
        files: [LocalAPIViewFileItem],
        chapters: [LocalAPIViewChapterItem],
        selectedChapterIndex: Int?,
        previousTaskID: UUID?,
        nextTaskID: UUID?,
        auth: String,
        viewOptions: String,
        preferenceOptions: String,
        preferences: APIViewPreferences,
        lazyLoadingDefault: Bool
    ) -> String {
        let uid = id.uuidString
        let safeTitle = Self.escape(title)
        let imageIndexes = files.enumerated()
            .filter { $0.element.mediaType == "image" }
            .map(\.offset)
        let readerHTML = imageIndexes.isEmpty
            ? #"<span class="nav disabled">Reader</span>"#
            : #"<a class="nav" href="/view?uid=\#(uid)&mode=book&page=0\#(auth)\#(viewOptions)">Reader</a>"#
        let scrollHTML = imageIndexes.isEmpty
            ? #"<span class="nav disabled">Scroll</span>"#
            : #"<a class="nav" href="/view?uid=\#(uid)&mode=scroll\#(auth)\#(viewOptions)">Scroll</a>"#
        let previousHTML = previousTaskID.map {
            #"<a class="nav" data-prev href="/view?uid=\#($0.uuidString)\#(auth)\#(preferenceOptions)">Previous</a>"#
        } ?? #"<span class="nav disabled">Previous</span>"#
        let nextHTML = nextTaskID.map {
            #"<a class="nav" data-next href="/view?uid=\#($0.uuidString)\#(auth)\#(preferenceOptions)">Next</a>"#
        } ?? #"<span class="nav disabled">Next</span>"#

        let chapterNavigation = chapterNavigationHTML(
            chapters: chapters,
            selectedIndex: selectedChapterIndex,
            uid: uid,
            auth: auth,
            options: preferenceOptions
        )
        let chapterNavigationScript = selectedChapterIndex == nil ? "" : """
          <script>
            document.addEventListener('keydown', event => {
              if (event.ctrlKey || event.altKey || event.shiftKey || event.metaKey) return;
              if (event.key === 'ArrowLeft') {
                const previous = document.getElementById('prev');
                if (previous && previous.href) location.href = previous.href;
              }
              if (event.key === 'ArrowRight') {
                const next = document.getElementById('next');
                if (next && next.href) location.href = next.href;
              }
            });
          </script>
        """
        let chapterHTML: String
        if chapters.count > 1 {
            chapterHTML = """
            <section class="chapters" aria-label="Chapters">
              \(chapters.map { chapter in
                  let chapterTitle = Self.escape(chapter.title)
                  let fileCount = "\(chapter.indexes.count) files"
                  let start = chapter.indexes.first ?? 0
                  let end = chapter.indexes.last ?? 0
                  let href = "/view?uid=\(uid)&start=\(start)&end=\(end)\(auth)\(preferenceOptions)&title=\(Self.queryComponent(chapter.title))"
                  return "<a href=\"\(href)\"><strong>\(chapterTitle)</strong><span>\(fileCount)</span></a>"
              }.joined(separator: "\n"))
            </section>
            """
        } else {
            chapterHTML = ""
        }

        let gridHTML: String
        if imageIndexes.count > 1 {
            gridHTML = """
            <section class="gallery-grid" aria-label="Image navigation">
              \(imageIndexes.map { index in
                  let file = files[index]
                  let name = Self.escape(file.relativePath)
                  let thumbURL = "/thumb?uid=\(uid)&index=\(file.originalIndex)\(auth)"
                  let detailURL = "/view?uid=\(uid)&index=\(file.originalIndex)\(auth)\(viewOptions)"
                  return "<a href=\"\(detailURL)\"><img src=\"\(thumbURL)\" alt=\"\(name)\"><span>\(index + 1)</span></a>"
              }.joined(separator: "\n"))
            </section>
            """
        } else {
            gridHTML = ""
        }

        let fileHTML: String
        if files.isEmpty {
            fileHTML = #"<div class="empty">No output files</div>"#
        } else {
            fileHTML = files.enumerated().map { index, file in
                let fileURL = "/file?uid=\(uid)&index=\(file.originalIndex)\(auth)"
                let name = Self.escape(file.relativePath)
                switch file.mediaType {
                case "image":
                    let image = pageImage(
                        src: fileURL,
                        id: "page\(index)",
                        alt: name,
                        preferences: preferences,
                        lazyLoadingDefault: lazyLoadingDefault
                    )
                    return #"<figure id="file-\#(index)">\#(image)<figcaption>\#(name)</figcaption></figure>"#
                case "video":
                    return #"<figure id="file-\#(index)"><video controls class="page" id="page\#(index)" preload="metadata" src="\#(fileURL)"></video><figcaption>\#(name)</figcaption></figure>"#
                case "audio":
                    return #"<figure id="file-\#(index)"><audio controls class="page" id="page\#(index)" src="\#(fileURL)"></audio><figcaption>\#(name)</figcaption></figure>"#
                default:
                    return #"<p class="file page" id="file-\#(index)" data-page-id="page\#(index)"><a href="\#(fileURL)">\#(name)</a></p>"#
                }
            }.joined(separator: "\n")
        }

        return """
        <!doctype html>
        <html\(preferences.htmlDirectionAttribute)>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <script src="/lazysizes.js" defer></script>
          <title>\(safeTitle)</title>
          <style>
            body { margin: 0; \(preferences.bodyCSS) font: 13px \(LocalAPIHTMLStyle.fontStack); }
            header { position: sticky; top: 0; z-index: 2; padding: 12px 14px; \(preferences.headerCSS) backdrop-filter: blur(10px); }
            h1 { font-size: 16px; margin: 0 0 4px; }
            .meta { color: #5f6368; overflow-wrap: anywhere; }
            .toolbar { display: flex; gap: 8px; align-items: center; margin-top: 10px; }
            .nav { display: inline-flex; min-height: 30px; align-items: center; padding: 0 10px; border-radius: 6px; \(preferences.navCSS) text-decoration: none; }
            .disabled { \(preferences.disabledCSS) }
            main { max-width: 980px; margin: 0 auto; padding: 14px; }
            .chapters { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 14px; }
            .chapters a { display: inline-flex; flex-direction: column; gap: 2px; min-width: 120px; padding: 9px 10px; border: 1px solid \(preferences.isDark ? "#333" : "#ddd"); background: \(preferences.isDark ? "#171717" : "white"); color: inherit; text-decoration: none; }
            .chapters span { color: #5f6368; font-size: 12px; }
            .chapter-nav { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-bottom: 14px; }
            .gallery-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(92px, 1fr)); gap: 8px; margin-bottom: 14px; }
            .gallery-grid a { position: relative; display: block; aspect-ratio: 1; overflow: hidden; border: 1px solid #ddd; background: white; color: white; }
            .gallery-grid img { width: 100%; height: 100%; object-fit: cover; background: #111; }
            .gallery-grid span { position: absolute; right: 6px; bottom: 5px; padding: 2px 5px; border-radius: 4px; background: rgba(0,0,0,.62); font-size: 11px; }
            figure { \(preferences.figureCSS) background: \(preferences.isDark ? "#171717" : "white"); border: 1px solid \(preferences.isDark ? "#333" : "#ddd"); }
            img, video { display: block; \(preferences.imageCSS) background: #111; }
            audio { width: 100%; }
            figcaption, .file { color: #5f6368; overflow-wrap: anywhere; }
            .empty { padding: 24px; background: white; border: 1px solid #ddd; text-align: center; color: #6b6f76; }
          </style>
        </head>
        <body class="view">
          <header>
            <h1>\(safeTitle)</h1>
            <div class="meta">\(Self.escape(source))</div>
            <div class="toolbar">\(previousHTML)<a class="nav" href="/webui\(auth.isEmpty ? "" : "?\(String(auth.dropFirst()))")">Queue</a>\(readerHTML)\(scrollHTML)\(nextHTML)</div>
          </header>
          <main>
            \(chapterNavigation)
            \(chapterHTML)
            \(gridHTML)
            \(fileHTML)
          </main>
          \(legacyKeydownScript(preferences: preferences))
          \(chapterNavigationScript)
        </body>
        </html>
        """
    }

    func fileViewPage(
        id: UUID,
        title: String,
        files: [LocalAPIViewFileItem],
        selectedPosition: Int,
        auth: String,
        viewOptions: String,
        preferences: APIViewPreferences,
        lazyLoadingDefault: Bool
    ) -> String {
        let uid = id.uuidString
        let file = files[selectedPosition]
        let safeTitle = Self.escape(title)
        let name = Self.escape(file.relativePath)
        let fileURL = "/file?uid=\(uid)&index=\(file.originalIndex)\(auth)"
        let allFilesURL = "/view?uid=\(uid)\(auth)\(viewOptions)"
        let deleteFileURL = "/delete_file?uid=\(uid)&index=\(file.originalIndex)\(auth)"
        let previousHTML = selectedPosition > 0
            ? #"<a class="nav" id="prev" data-prev href="/view?uid=\#(uid)&index=\#(files[selectedPosition - 1].originalIndex)\#(auth)\#(viewOptions)">Previous File</a>"#
            : #"<span class="nav disabled" id="prev">Previous File</span>"#
        let nextHTML = selectedPosition + 1 < files.count
            ? #"<a class="nav" id="next" data-next href="/view?uid=\#(uid)&index=\#(files[selectedPosition + 1].originalIndex)\#(auth)\#(viewOptions)">Next File</a>"#
            : #"<span class="nav disabled" id="next">Next File</span>"#
        let mediaHTML: String
        switch file.mediaType {
        case "image":
            let image = pageImage(
                src: fileURL,
                id: "page\(selectedPosition)",
                alt: name,
                preferences: preferences,
                lazyLoadingDefault: lazyLoadingDefault
            )
            mediaHTML = #"<figure class="detail">\#(image)<figcaption>\#(name)</figcaption></figure>"#
        case "video":
            mediaHTML = #"<figure class="detail"><video controls class="page" id="page\#(selectedPosition)" autoplay preload="metadata" src="\#(fileURL)"></video><figcaption>\#(name)</figcaption></figure>"#
        case "audio":
            mediaHTML = #"<figure class="detail"><audio controls class="page" id="page\#(selectedPosition)" autoplay src="\#(fileURL)"></audio><figcaption>\#(name)</figcaption></figure>"#
        default:
            mediaHTML = #"<p class="detail-file page" data-page-id="page\#(selectedPosition)"><a href="\#(fileURL)">\#(name)</a></p>"#
        }

        return """
        <!doctype html>
        <html\(preferences.htmlDirectionAttribute)>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <script src="/lazysizes.js" defer></script>
          <title>\(safeTitle) - \(name)</title>
          <style>
            body { margin: 0; \(preferences.bodyCSS) font: 13px \(LocalAPIHTMLStyle.fontStack); }
            header { position: sticky; top: 0; z-index: 2; padding: 10px 14px; \(preferences.headerCSS) backdrop-filter: blur(10px); }
            h1 { font-size: 15px; margin: 0 0 3px; color: \(preferences.isDark ? "white" : "#202124"); }
            .meta { color: #bdc1c6; overflow-wrap: anywhere; }
            .toolbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 9px; }
            .nav { display: inline-flex; min-height: 30px; align-items: center; padding: 0 10px; border-radius: 6px; \(preferences.navCSS) text-decoration: none; border: 0; cursor: pointer; font: inherit; }
            .danger { color: #ff8a80; }
            .disabled { \(preferences.disabledCSS) }
            main { min-height: calc(100vh - 90px); display: grid; place-items: center; padding: 14px; box-sizing: border-box; }
            figure { width: 100%; max-width: 1400px; margin: 0; }
            img, video { display: block; \(preferences.imageCSS) \(preferences.mediaMarginCSS) background: #050505; }
            audio { width: min(820px, 100%); }
            figcaption, .detail-file { margin: 10px 0 0; color: #bdc1c6; text-align: center; overflow-wrap: anywhere; }
            .detail-file a { color: white; }
          </style>
        </head>
        <body class="view">
          <header>
            <h1>\(safeTitle)</h1>
            <div class="meta">\(selectedPosition + 1) / \(files.count) · \(name)</div>
            <div class="toolbar">\(previousHTML)<a class="nav" href="\(allFilesURL)">All Files</a>\(nextHTML)<button class="nav danger" type="button" onclick="deleteCurrentFile()">Delete File</button></div>
          </header>
          <main>
            \(mediaHTML)
          </main>
          \(legacyKeydownScript(preferences: preferences))
          <script>
            document.addEventListener('keydown', event => {
              if (event.key === '\(preferences.previousKey)') {
                const previous = document.querySelector('[data-prev]');
                if (previous) location.href = previous.href;
              }
              if (event.key === '\(preferences.nextKey)' || event.key === ' ') {
                const next = document.querySelector('[data-next]');
                if (next) location.href = next.href;
              }
              if (event.key === 'Escape') {
                location.href = \(Self.javascriptStringLiteral(allFilesURL));
              }
            });
            \(wheelNavigationScript())
            async function deleteCurrentFile() {
              if (!confirm('Delete this output file?')) return;
              const response = await fetch(\(Self.javascriptStringLiteral(deleteFileURL)), { method: 'POST' });
              if (response.ok) {
                location.href = \(Self.javascriptStringLiteral(allFilesURL));
              } else {
                alert(await response.text());
              }
            }
          </script>
        </body>
        </html>
        """
    }

    func bookViewPage(
        id: UUID,
        title: String,
        images: [LocalAPIViewFileItem],
        pageText: String?,
        previousTaskID: UUID?,
        nextTaskID: UUID?,
        auth: String,
        viewOptions: String,
        preferenceOptions: String,
        preferences: APIViewPreferences,
        lazyLoadingDefault: Bool
    ) -> String {
        guard !images.isEmpty else {
            return messagePage(
                title: "No images",
                message: "This output has no image files for reader mode."
            )
        }

        let uid = id.uuidString
        let safeTitle = Self.escape(title)
        let requestedPage = Int(pageText ?? "0") ?? 0
        let page = min(max(requestedPage, 0), images.count - 1)
        let file = images[page]
        let name = Self.escape(file.relativePath)
        let imageURL = "/file?uid=\(uid)&index=\(file.originalIndex)\(auth)"
        let allFilesURL = "/view?uid=\(uid)\(auth)\(viewOptions)"

        let previousHTML: String
        if page > 0 {
            previousHTML = #"<a class="nav" id="prev" data-prev href="/view?uid=\#(uid)&mode=book&page=\#(page - 1)\#(auth)\#(viewOptions)">Previous Page</a>"#
        } else if let previousTaskID {
            previousHTML = #"<a class="nav" id="prev" data-prev href="/view?uid=\#(previousTaskID.uuidString)&mode=book\#(auth)\#(preferenceOptions)">Previous Task</a>"#
        } else {
            previousHTML = #"<span class="nav disabled" id="prev">Previous Page</span>"#
        }

        let nextHTML: String
        if page + 1 < images.count {
            nextHTML = #"<a class="nav" id="next" data-next href="/view?uid=\#(uid)&mode=book&page=\#(page + 1)\#(auth)\#(viewOptions)">Next Page</a>"#
        } else if let nextTaskID {
            nextHTML = #"<a class="nav" id="next" data-next href="/view?uid=\#(nextTaskID.uuidString)&mode=book\#(auth)\#(preferenceOptions)">Next Task</a>"#
        } else {
            nextHTML = #"<span class="nav disabled" id="next">Next Page</span>"#
        }

        return """
        <!doctype html>
        <html\(preferences.htmlDirectionAttribute)>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <script src="/lazysizes.js" defer></script>
          <title>\(safeTitle) - Reader</title>
          <style>
            body { margin: 0; \(preferences.bodyCSS) font: 13px \(LocalAPIHTMLStyle.fontStack); }
            header { position: sticky; top: 0; z-index: 2; padding: 10px 14px; \(preferences.headerCSS) backdrop-filter: blur(10px); }
            h1 { font-size: 15px; margin: 0 0 3px; color: \(preferences.isDark ? "white" : "#202124"); }
            .meta { color: #bdc1c6; overflow-wrap: anywhere; }
            .toolbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 9px; }
            .nav { display: inline-flex; min-height: 30px; align-items: center; padding: 0 10px; border-radius: 6px; \(preferences.navCSS) text-decoration: none; }
            .disabled { \(preferences.disabledCSS) }
            main { min-height: calc(100vh - 90px); display: grid; place-items: center; padding: 14px; box-sizing: border-box; }
            figure { margin: 0; width: 100%; }
            img { display: block; \(preferences.imageCSS) \(preferences.mediaMarginCSS) background: #050505; }
            figcaption { margin-top: 10px; color: #bdc1c6; text-align: center; overflow-wrap: anywhere; }
          </style>
        </head>
        <body class="view">
          <header>
            <h1>\(safeTitle)</h1>
            <div class="meta">Reader \(page + 1) / \(images.count) - \(name)</div>
            <div class="toolbar">\(previousHTML)<a class="nav" href="\(allFilesURL)">All Files</a>\(nextHTML)</div>
          </header>
          <main>
            <figure>
              \(pageImage(
                  src: imageURL,
                  id: "page\(page)",
                  alt: name,
                  preferences: preferences,
                  lazyLoadingDefault: lazyLoadingDefault
              ))
              <figcaption>\(name)</figcaption>
            </figure>
          </main>
          \(legacyKeydownScript(preferences: preferences))
          <script>
            document.addEventListener('keydown', event => {
              if (event.key === '\(preferences.previousKey)') {
                const previous = document.querySelector('[data-prev]');
                if (previous) location.href = previous.href;
              }
              if (event.key === '\(preferences.nextKey)' || event.key === ' ') {
                const next = document.querySelector('[data-next]');
                if (next) location.href = next.href;
              }
              if (event.key === 'Escape') {
                location.href = \(Self.javascriptStringLiteral(allFilesURL));
              }
            });
            \(wheelNavigationScript())
          </script>
        </body>
        </html>
        """
    }

    func scrollViewPage(
        id: UUID,
        title: String,
        images: [LocalAPIScrollViewImageItem],
        previousTaskID: UUID?,
        nextTaskID: UUID?,
        auth: String,
        viewOptions: String,
        preferenceOptions: String,
        preferences: APIViewPreferences,
        lazyLoadingDefault: Bool
    ) -> String {
        guard !images.isEmpty else {
            return messagePage(
                title: "No images",
                message: "This output has no image files for scroll reader mode."
            )
        }

        let uid = id.uuidString
        let safeTitle = Self.escape(title)
        let allFilesURL = "/view?uid=\(uid)\(auth)\(viewOptions)"
        let bookURL = "/view?uid=\(uid)&mode=book&page=0\(auth)\(viewOptions)"
        let previousHTML = previousTaskID.map {
            #"<a class="nav" id="prev" data-prev href="/view?uid=\#($0.uuidString)&mode=scroll\#(auth)\#(preferenceOptions)">Previous Task</a>"#
        } ?? #"<span class="nav disabled" id="prev">Previous Task</span>"#
        let nextHTML = nextTaskID.map {
            #"<a class="nav" id="next" data-next href="/view?uid=\#($0.uuidString)&mode=scroll\#(auth)\#(preferenceOptions)">Next Task</a>"#
        } ?? #"<span class="nav disabled" id="next">Next Task</span>"#
        let figuresHTML = images.enumerated().map { displayIndex, image in
            let name = Self.escape(image.relativePath)
            let imageURL = "/file?uid=\(uid)&index=\(image.originalIndex)\(auth)"
            let imageHTML = pageImage(
                src: imageURL,
                id: "page\(displayIndex)",
                alt: name,
                preferences: preferences,
                lazyLoadingDefault: lazyLoadingDefault
            )
            return """
            <figure id="file-\(image.position)">
              \(imageHTML)
              <figcaption>\(displayIndex + 1) / \(images.count) - \(name)</figcaption>
            </figure>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html\(preferences.htmlDirectionAttribute)>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <script src="/lazysizes.js" defer></script>
          <title>\(safeTitle) - Scroll Reader</title>
          <style>
            body { margin: 0; \(preferences.bodyCSS) font: 13px \(LocalAPIHTMLStyle.fontStack); }
            header { position: sticky; top: 0; z-index: 2; padding: 10px 14px; \(preferences.headerCSS) backdrop-filter: blur(10px); }
            h1 { font-size: 15px; margin: 0 0 3px; color: \(preferences.isDark ? "white" : "#202124"); }
            .meta { color: #bdc1c6; overflow-wrap: anywhere; }
            .toolbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 9px; }
            .nav { display: inline-flex; min-height: 30px; align-items: center; padding: 0 10px; border-radius: 6px; \(preferences.navCSS) text-decoration: none; }
            .disabled { \(preferences.disabledCSS) }
            main { width: min(1400px, 100%); margin: 0 auto; padding: 14px; box-sizing: border-box; }
            figure { \(preferences.figureCSS) background: \(preferences.isDark ? "#171717" : "white"); border: 1px solid \(preferences.isDark ? "#333" : "#ddd"); }
            img { display: block; \(preferences.imageCSS) \(preferences.mediaMarginCSS) background: #050505; }
            figcaption { margin-top: 10px; color: #bdc1c6; text-align: center; overflow-wrap: anywhere; }
          </style>
        </head>
        <body class="view">
          <header>
            <h1>\(safeTitle)</h1>
            <div class="meta">Scroll Reader - \(images.count) images</div>
            <div class="toolbar">\(previousHTML)<a class="nav" href="\(allFilesURL)">All Files</a><a class="nav" href="\(bookURL)">Paged Reader</a>\(nextHTML)</div>
          </header>
          <main>
            \(figuresHTML)
          </main>
          \(legacyKeydownScript(preferences: preferences))
          <script>
            document.addEventListener('keydown', event => {
              if (event.key === '\(preferences.previousKey)') {
                const previous = document.querySelector('[data-prev]');
                if (previous) location.href = previous.href;
              }
              if (event.key === '\(preferences.nextKey)') {
                const next = document.querySelector('[data-next]');
                if (next) location.href = next.href;
              }
              if (event.key === 'Escape') {
                location.href = \(Self.javascriptStringLiteral(allFilesURL));
              }
            });
            \(wheelNavigationScript(edgeOnly: true))
          </script>
        </body>
        </html>
        """
    }

    func chapterNavigationHTML(
        chapters: [LocalAPIViewChapterItem],
        selectedIndex: Int?,
        uid: String,
        auth: String,
        options: String
    ) -> String {
        guard chapters.count > 1,
              let selectedIndex,
              chapters.indices.contains(selectedIndex) else {
            return ""
        }

        func chapterURL(_ index: Int) -> String {
            let chapter = chapters[index]
            let start = chapter.indexes.first ?? 0
            let end = chapter.indexes.last ?? 0
            return "/view?uid=\(uid)&start=\(start)&end=\(end)\(auth)\(options)&title=\(Self.queryComponent(chapter.title))"
        }

        let previousHTML = selectedIndex > 0
            ? #"<a class="nav" id="prev" href="\#(chapterURL(selectedIndex - 1))">Previous Chapter</a>"#
            : #"<span class="nav disabled" id="prev">Previous Chapter</span>"#
        let nextHTML = selectedIndex + 1 < chapters.count
            ? #"<a class="nav" id="next" href="\#(chapterURL(selectedIndex + 1))">Next Chapter</a>"#
            : #"<span class="nav disabled" id="next">Next Chapter</span>"#
        let listURL = "/view?uid=\(uid)\(auth)\(options)"
        let currentTitle = Self.escape(chapters[selectedIndex].title)
        return """
        <nav class="chapter-nav" aria-label="Chapter navigation">
          \(previousHTML)
          <a class="nav" href="\(listURL)">All Chapters</a>
          \(nextHTML)
          <span class="summary">\(currentTitle)</span>
        </nav>
        """
    }

    func multiViewPage(
        title: String,
        tasks: [LocalAPIMultiViewTaskItem],
        auth: String,
        viewOptions: String,
        preferences: APIViewPreferences,
        lazyLoadingDefault: Bool
    ) -> String {
        let safeTitle = Self.escape(title)
        let sectionHTML = tasks.map { task in
            let uid = task.id.uuidString
            let jobTitle = Self.escape(
                task.title.isEmpty ? task.source : task.title
            )
            let source = Self.escape(task.source)
            let imageCount = task.files.filter {
                $0.mediaType == "image"
            }.count
            let summary = "\(task.files.count) file\(task.files.count == 1 ? "" : "s")\(imageCount > 0 ? ", \(imageCount) image\(imageCount == 1 ? "" : "s")" : "")"
            let readerHTML = imageCount > 0
                ? #"<a class="nav" href="/view?uid=\#(uid)&mode=book&page=0\#(auth)\#(viewOptions)">Reader</a><a class="nav" href="/view?uid=\#(uid)&mode=scroll\#(auth)\#(viewOptions)">Scroll</a>"#
                : #"<span class="nav disabled">Reader</span><span class="nav disabled">Scroll</span>"#

            let filesHTML: String
            if task.files.isEmpty {
                filesHTML = #"<div class="empty">No output files</div>"#
            } else {
                filesHTML = task.files.enumerated().map { displayIndex, file in
                    let fileURL = "/file?uid=\(uid)&index=\(file.originalIndex)\(auth)"
                    let detailURL = "/view?uid=\(uid)&index=\(file.originalIndex)\(auth)\(viewOptions)"
                    let name = Self.escape(file.relativePath)
                    switch file.mediaType {
                    case "image":
                        let image = pageImage(
                            src: fileURL,
                            id: "page-\(uid)-\(displayIndex)",
                            alt: name,
                            preferences: preferences,
                            lazyLoadingDefault: lazyLoadingDefault
                        )
                        return #"<figure id="task-\#(uid)-file-\#(displayIndex)"><a href="\#(detailURL)">\#(image)</a><figcaption>\#(displayIndex + 1). \#(name)</figcaption></figure>"#
                    case "video":
                        return #"<figure id="task-\#(uid)-file-\#(displayIndex)"><video controls class="page" id="page-\#(uid)-\#(displayIndex)" preload="metadata" src="\#(fileURL)"></video><figcaption>\#(displayIndex + 1). \#(name)</figcaption></figure>"#
                    case "audio":
                        return #"<figure id="task-\#(uid)-file-\#(displayIndex)"><audio controls class="page" id="page-\#(uid)-\#(displayIndex)" src="\#(fileURL)"></audio><figcaption>\#(displayIndex + 1). \#(name)</figcaption></figure>"#
                    default:
                        return #"<p class="file page" id="task-\#(uid)-file-\#(displayIndex)" data-page-id="page-\#(uid)-\#(displayIndex)"><a href="\#(detailURL)">\#(displayIndex + 1). \#(name)</a></p>"#
                    }
                }.joined(separator: "\n")
            }

            return """
            <section class="task-section" id="task-\(uid)">
              <header class="task-header">
                <h2>\(jobTitle)</h2>
                <div class="meta">\(source)</div>
                <div class="toolbar"><span class="summary">\(summary)</span><a class="nav" href="/view?uid=\(uid)\(auth)\(viewOptions)">Open</a>\(readerHTML)</div>
              </header>
              <div class="task-files">
                \(filesHTML)
              </div>
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html\(preferences.htmlDirectionAttribute)>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <script src="/lazysizes.js" defer></script>
          <title>\(safeTitle) - Hitomi Badayo</title>
          <style>
            body { margin: 0; \(preferences.bodyCSS) font: 13px \(LocalAPIHTMLStyle.fontStack); }
            body > header { position: sticky; top: 0; z-index: 2; padding: 12px 14px; \(preferences.headerCSS) backdrop-filter: blur(10px); }
            h1 { font-size: 16px; margin: 0 0 4px; }
            h2 { font-size: 15px; margin: 0 0 4px; }
            .meta, .summary, figcaption, .file { color: #5f6368; overflow-wrap: anywhere; }
            .toolbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 9px; }
            .nav { display: inline-flex; min-height: 30px; align-items: center; padding: 0 10px; border-radius: 6px; \(preferences.navCSS) text-decoration: none; }
            .disabled { \(preferences.disabledCSS) }
            main.multi-view { max-width: 1180px; margin: 0 auto; padding: 14px; }
            .task-section { margin: 0 0 18px; }
            .task-header { padding: 12px 0 10px; border-bottom: 1px solid \(preferences.isDark ? "#333" : "#ddd"); }
            .task-files { display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); gap: 10px; padding-top: 12px; }
            figure { margin: 0; padding: 8px; background: \(preferences.isDark ? "#171717" : "white"); border: 1px solid \(preferences.isDark ? "#333" : "#ddd"); }
            img, video { display: block; width: 100%; height: auto; max-height: 420px; object-fit: contain; background: #111; }
            audio { width: 100%; }
            figcaption { margin-top: 7px; font-size: 12px; }
            .file, .empty { padding: 12px; background: \(preferences.isDark ? "#171717" : "white"); border: 1px solid \(preferences.isDark ? "#333" : "#ddd"); }
            a { color: #1a73e8; }
          </style>
        </head>
        <body class="view">
          <header>
            <h1>\(safeTitle)</h1>
            <div class="meta">Multi-task browser view - \(tasks.count) tasks</div>
            <div class="toolbar"><a class="nav" href="/webui\(auth.isEmpty ? "" : "?\(String(auth.dropFirst()))")">Queue</a></div>
          </header>
          <main class="multi-view">
            \(sectionHTML)
          </main>
          \(legacyKeydownScript(preferences: preferences))
        </body>
        </html>
        """
    }

    func messagePage(title: String, message: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(Self.escape(title))</title></head>
        <body style="font:14px \(LocalAPIHTMLStyle.fontStack);padding:24px;">
          <h1>\(Self.escape(title))</h1>
          <p>\(Self.escape(message))</p>
        </body></html>
        """
    }

    func pageImage(
        src: String,
        id: String,
        alt: String,
        preferences: APIViewPreferences,
        lazyLoadingDefault: Bool
    ) -> String {
        if preferences.effectiveLazyLoading(defaultValue: lazyLoadingDefault) {
            return #"<img class="page lazyload" src="/loading.gif" data-src="\#(src)" id="\#(id)" alt="\#(alt)">"#
        }
        return #"<img class="page" src="\#(src)" id="\#(id)" alt="\#(alt)">"#
    }

    func legacyKeydownScript(preferences: APIViewPreferences) -> String {
        """
        <script>
          function refresh_preview(){
            var stamp = Date.now().toString();
            var updated = false;
            function refreshedURL(value){
              try {
                var url = new URL(value, location.href);
                url.searchParams.set("refresh", stamp);
                return url.pathname + url.search + url.hash;
              } catch (error) {
                return value;
              }
            }
            document.querySelectorAll("img.page, video.page, audio.page").forEach(function(element){
              ["src", "data-src"].forEach(function(attribute){
                var value = element.getAttribute(attribute);
                if (!value || value.indexOf("/loading.gif") >= 0) return;
                element.setAttribute(attribute, refreshedURL(value));
                updated = true;
              });
              if (element.tagName === "VIDEO" || element.tagName === "AUDIO") element.load();
            });
            if (!updated) location.reload();
          }
          function keydown(e){
            var key = e.keyCode || e.which;
            var alt = e.altKey;
            var ctrl = e.ctrlKey;
            var shift = e.shiftKey;
            var meta = e.metaKey;
            if (key == 116 || ((ctrl || meta) && key == 82)) {
              e.preventDefault();
              refresh_preview();
              return;
            }
            if (ctrl || alt || shift) return;
            var prev = document.getElementById("prev") || document.querySelector("[data-prev]");
            var next = document.getElementById("next") || document.querySelector("[data-next]");
            if (key == \(preferences.previousKeyCode) && prev) prev.click();
            if (key == \(preferences.nextKeyCode) && next) next.click();
          }
          document.addEventListener("keydown", keydown, false);
        </script>
        """
    }

    func wheelNavigationScript(edgeOnly: Bool = false) -> String {
        """
        (() => {
          const edgeOnly = \(edgeOnly ? "true" : "false");
          const threshold = 90;
          let accumulated = 0;
          let lastDirection = 0;

          function interactiveTarget(target) {
            return target?.closest?.('a, button, input, textarea, select, audio, video, [contenteditable="true"]');
          }

          function canNavigate(direction) {
            if (!edgeOnly) return true;
            const scroller = document.scrollingElement || document.documentElement;
            const atTop = scroller.scrollTop <= 2;
            const atBottom = Math.ceil(scroller.scrollTop + window.innerHeight) >= scroller.scrollHeight - 2;
            return direction < 0 ? atTop : atBottom;
          }

          function navigate(direction) {
            const link = document.querySelector(direction < 0 ? '[data-prev]' : '[data-next]');
            if (!link || !link.href) return false;
            location.href = link.href;
            return true;
          }

          document.addEventListener('wheel', event => {
            if (event.ctrlKey || event.altKey || event.metaKey || event.shiftKey) return;
            if (interactiveTarget(event.target)) return;
            const primaryDelta = Math.abs(event.deltaY) >= Math.abs(event.deltaX) ? event.deltaY : event.deltaX;
            if (Math.abs(primaryDelta) < 1) return;
            const direction = primaryDelta > 0 ? 1 : -1;
            if (!canNavigate(direction)) {
              accumulated = 0;
              lastDirection = direction;
              return;
            }
            if (direction !== lastDirection) accumulated = 0;
            accumulated += primaryDelta;
            lastDirection = direction;
            if (Math.abs(accumulated) < threshold) return;
            if (navigate(direction)) event.preventDefault();
            accumulated = 0;
          }, { passive: false });
        })();
        """
    }

    private static func escape(_ value: String) -> String {
        LocalAPIHTMLStyle.escape(value)
    }

    private static func queryComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
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
