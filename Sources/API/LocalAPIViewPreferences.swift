import Foundation

struct APIViewPreferences {
    var theme: String
    var fit: String
    var direction: String
    var gap: String
    var align: String
    var sort: String
    var descending: Bool
    var lazyLoading: Bool?
    private var explicitKeys: Set<String>

    init(query: [String: String]) {
        explicitKeys = Set(query.keys.map(Self.normalizedQueryKey))
        theme = Self.themeValue(query)
        fit = Self.fitValue(query)
        direction = Self.directionValue(query)
        gap = Self.gapValue(query)
        align = Self.alignValue(query)
        let sortValue = Self.sortValue(query)
        sort = sortValue.sort
        descending = sortValue.descending || Self.descendingValue(query)
        lazyLoading = Self.lazyLoadingValue(query)
    }

    var queryItems: [(String, String)] {
        [
            shouldEmit(canonical: "theme", aliases: ["theme", "style", "color", "bg", "background", "background_color", "bg_color", "bgcolor", "viewer_theme", "viewer_style", "viewer_color", "viewercolor", "color_scheme", "colorscheme", "scheme", "palette", "darkmode", "dark_mode", "lightmode", "light_mode", "dark", "black", "night", "light", "white", "day"], value: theme, defaultValue: "dark") ? ("theme", theme) : nil,
            shouldEmit(canonical: "fit", aliases: ["fit", "size", "image_fit", "imagefit", "image_size", "imagesize", "img_fit", "imgfit", "img_size", "imgsize", "image_scale", "imagescale", "scale_mode", "scalemode", "view_size", "viewsize", "fit_to_width", "fit_width", "fitwidth", "fittowidth", "fit_to_height", "fit_height", "fitheight", "fittoheight", "fit_screen", "fitscreen", "fit_to_screen", "fittoscreen", "zoom", "scale"], value: fit, defaultValue: "contain") ? ("fit", fit) : nil,
            shouldEmit(canonical: "dir", aliases: ["dir", "direction", "reading", "reading_direction", "readingdirection", "reader_direction", "readerdirection", "reader_dir", "readerdir", "read_direction", "read_dir", "view_direction", "viewdirection", "readmode", "reading_mode", "manga_mode", "page_direction", "pagedirection", "page_dir", "pagedir", "rtl", "ltr"], value: direction, defaultValue: "ltr") ? ("dir", direction) : nil,
            shouldEmit(canonical: "gap", aliases: ["gap", "spacing", "space", "margin", "padding", "image_gap", "imagegap", "page_gap", "pagegap", "page_spacing", "pagespacing", "reader_gap", "readergap", "reader_spacing", "readerspacing", "no_gap", "nogap"], value: gap, defaultValue: "normal") ? ("gap", gap) : nil,
            shouldEmit(canonical: "align", aliases: ["align", "position", "pos", "x", "h_align", "halign", "horizontal_align", "horizontalalign", "horizontal_position", "horizontalposition", "horizontal", "page_align", "pagealign", "page_position", "pageposition", "image_align", "imagealign", "image_position", "imageposition", "viewer_position", "viewerposition", "hpos"], value: align, defaultValue: "center") ? ("align", align) : nil,
            lazyLoading.map { ("lazy", $0 ? "1" : "0") },
            shouldEmit(canonical: "sort", aliases: ["sort", "sort_by", "sortby", "order_by", "orderby", "order", "file_order", "fileorder", "filename_sort", "filenamesort"], value: sort, defaultValue: "path") ? ("sort", sort) : nil,
            descending ? ("reverse", "1") : nil
        ].compactMap { $0 }
    }

    private func shouldEmit(canonical: String, aliases: [String], value: String, defaultValue: String) -> Bool {
        let normalizedCanonical = Self.normalizedQueryKey(canonical)
        return value != defaultValue || aliases.contains { alias in
            explicitKeys.contains(Self.normalizedQueryKey(alias)) || explicitKeys.contains(normalizedCanonical)
        }
    }

    var htmlDirectionAttribute: String {
        direction == "rtl" ? #" dir="rtl""# : ""
    }

    var isDark: Bool {
        theme == "dark"
    }

    func effectiveLazyLoading(defaultValue: Bool) -> Bool {
        lazyLoading ?? defaultValue
    }

    var bodyCSS: String {
        isDark
            ? #"background: #111; color: #f8f9fa;"#
            : #"background: #f5f5f3; color: #202124;"#
    }

    var headerCSS: String {
        isDark
            ? #"background: rgba(20,20,20,.92); border-bottom: 1px solid #333;"#
            : #"background: rgba(255,255,255,.94); border-bottom: 1px solid #ddd;"#
    }

    var navCSS: String {
        isDark
            ? #"border: 1px solid #5f6368; background: #202124; color: white;"#
            : #"border: 1px solid #c8c8c8; background: white; color: #202124;"#
    }

    var disabledCSS: String {
        isDark
            ? #"color: #80868b; background: #171717;"#
            : #"color: #9aa0a6; background: #f1f3f4;"#
    }

    var figureCSS: String {
        switch gap {
        case "none":
            return "margin: 0; padding: 0;"
        case "compact":
            return "margin: 0 0 6px; padding: 6px;"
        case "wide":
            return "margin: 0 0 28px; padding: 14px;"
        default:
            return "margin: 0 0 14px; padding: 10px;"
        }
    }

    var imageCSS: String {
        switch fit {
        case "width":
            return "width: 100%; height: auto; max-height: none; object-fit: contain;"
        case "height":
            return "width: auto; max-width: 100%; max-height: calc(100vh - 150px); object-fit: contain;"
        case "original":
            return "width: auto; max-width: none; max-height: none; object-fit: contain;"
        default:
            return "width: 100%; height: auto; max-height: calc(100vh - 150px); object-fit: contain;"
        }
    }

    var mediaMarginCSS: String {
        switch align {
        case "left":
            return "margin: 0 auto 0 0;"
        case "right":
            return "margin: 0 0 0 auto;"
        default:
            return "margin: 0 auto;"
        }
    }

    var previousKey: String {
        direction == "rtl" ? "ArrowRight" : "ArrowLeft"
    }

    var nextKey: String {
        direction == "rtl" ? "ArrowLeft" : "ArrowRight"
    }

    var previousKeyCode: Int {
        direction == "rtl" ? 39 : 37
    }

    var nextKeyCode: Int {
        direction == "rtl" ? 37 : 39
    }

    private static func allowed(_ value: String?, values: Set<String>, defaultValue: String) -> String {
        let normalized = value?.trimmed.lowercased() ?? ""
        return values.contains(normalized) ? normalized : defaultValue
    }

    private static func themeValue(_ query: [String: String]) -> String {
        if let white = firstPresentQueryValue(query, keys: ["white", "day"]), !white.isEmpty {
            return truthy(white) ? "light" : "dark"
        }
        if let black = firstPresentQueryValue(query, keys: ["black", "night"]), !black.isEmpty {
            return truthy(black) ? "dark" : "light"
        }
        if let dark = firstPresentQueryValue(query, keys: ["dark"]), !dark.isEmpty {
            return truthy(dark) ? "dark" : "light"
        }
        if let light = firstPresentQueryValue(query, keys: ["light"]), !light.isEmpty {
            return truthy(light) ? "light" : "dark"
        }
        if let darkMode = firstPresentQueryValue(query, keys: ["darkmode", "dark_mode"]), !darkMode.isEmpty {
            return truthy(darkMode) ? "dark" : "light"
        }
        if let lightMode = firstPresentQueryValue(query, keys: ["lightmode", "light_mode"]), !lightMode.isEmpty {
            return truthy(lightMode) ? "light" : "dark"
        }
        let raw = firstQueryValue(query, keys: [
            "theme", "style", "color", "bg", "background", "background_color",
            "bg_color", "bgcolor", "viewer_theme", "viewer_style",
            "viewer_color", "viewercolor", "color_scheme", "colorscheme",
            "scheme", "palette", "darkmode", "dark_mode", "lightmode", "light_mode",
            "dark", "black", "night", "light", "white", "day"
        ]).trimmed.lowercased()
        switch raw {
        case "light", "white", "day", "bright", "original":
            return "light"
        case "dark", "black", "night":
            return "dark"
        default:
            return "dark"
        }
    }

    private static func fitValue(_ query: [String: String]) -> String {
        if let fitWidth = firstPresentQueryValue(query, keys: ["fit_to_width", "fit-to-width", "fit_width", "fit-width", "fitwidth", "fittowidth"]), !fitWidth.isEmpty, truthy(fitWidth) {
            return "width"
        }
        if let fitHeight = firstPresentQueryValue(query, keys: ["fit_to_height", "fit-to-height", "fit_height", "fit-height", "fitheight", "fittoheight"]), !fitHeight.isEmpty, truthy(fitHeight) {
            return "height"
        }
        if let fitScreen = firstPresentQueryValue(query, keys: ["fit_screen", "fit-screen", "fitscreen", "fit_to_screen", "fit-to-screen", "fittoscreen"]), !fitScreen.isEmpty, truthy(fitScreen) {
            return "contain"
        }
        let raw = firstQueryValue(query, keys: [
            "fit", "size", "image_fit", "imagefit", "image_size",
            "imagesize", "img_fit", "imgfit", "img_size", "imgsize",
            "image_scale", "imagescale", "scale_mode", "scalemode",
            "view_size", "viewsize", "fit_to_width", "fit_width", "fitwidth", "fittowidth",
            "fit_to_height", "fit_height", "fitheight", "fittoheight",
            "fit_screen", "fitscreen", "fit_to_screen", "fittoscreen", "zoom", "scale"
        ]).trimmed.lowercased()
        switch raw {
        case "full", "wide", "fitwidth", "fit_width", "fit-width", "fit_to_width", "fit-to-width", "fittowidth", "fullwidth", "full_width", "full-width", "pagewidth", "page_width", "page-width", "100", "100%":
            return "width"
        case "fitheight", "fit_height", "fit-height", "fit_to_height", "fit-to-height", "fittoheight", "fullheight", "full_height", "full-height", "pageheight", "page_height", "page-height":
            return "height"
        case "screen", "fit_screen", "fit-screen", "fitscreen", "fit_to_screen", "fit-to-screen", "fittoscreen", "contain", "scaled", "scale", "window":
            return "contain"
        case "auto", "actual", "actualsize", "actual_size", "actual-size", "originalsize", "original_size", "original-size", "real", "real-size", "real_size", "natural", "noscale", "no_scale", "no-scale", "none", "native":
            return "original"
        default:
            return allowed(raw, values: ["contain", "width", "height", "original"], defaultValue: "contain")
        }
    }

    private static func directionValue(_ query: [String: String]) -> String {
        if let rtl = firstPresentQueryValue(query, keys: ["rtl"]), !rtl.isEmpty {
            return truthy(rtl) ? "rtl" : "ltr"
        }
        if let ltr = firstPresentQueryValue(query, keys: ["ltr"]), !ltr.isEmpty {
            return truthy(ltr) ? "ltr" : "rtl"
        }
        let raw = firstQueryValue(query, keys: [
            "dir", "direction", "reading", "reading_direction", "readingdirection",
            "reader_direction", "readerdirection", "reader_dir", "readerdir",
            "read_direction", "read_dir", "view_direction", "viewdirection", "readmode", "reading_mode",
            "manga_mode", "page_direction", "pagedirection", "page_dir", "pagedir",
            "rtl", "ltr"
        ]).trimmed.lowercased()
        switch raw {
        case "rtl", "right", "right-to-left", "right_to_left", "righttoleft", "r2l", "manga", "japanese":
            return "rtl"
        case "ltr", "left", "left-to-right", "left_to_right", "lefttoright", "l2r", "webtoon", "korean", "vertical":
            return "ltr"
        default:
            return "ltr"
        }
    }

    private static func gapValue(_ query: [String: String]) -> String {
        if let noGap = firstPresentQueryValue(query, keys: ["no_gap", "nogap"]), !noGap.isEmpty, truthy(noGap) {
            return "none"
        }
        let raw = firstQueryValue(query, keys: [
            "gap", "spacing", "space", "margin", "padding",
            "image_gap", "imagegap", "page_gap", "pagegap",
            "page_spacing", "pagespacing", "reader_gap", "readergap",
            "reader_spacing", "readerspacing", "no_gap", "nogap"
        ]).trimmed.lowercased()
        switch raw {
        case "0", "zero", "off", "false", "no":
            return "none"
        case "small", "tight", "narrow":
            return "compact"
        case "large", "loose", "big", "roomy":
            return "wide"
        default:
            return allowed(raw, values: ["none", "compact", "normal", "wide"], defaultValue: "normal")
        }
    }

    private static func alignValue(_ query: [String: String]) -> String {
        let raw = firstQueryValue(query, keys: [
            "align", "position", "pos", "x", "h_align", "halign",
            "horizontal_align", "horizontalalign", "horizontal_position",
            "horizontalposition", "horizontal", "page_align", "pagealign",
            "page_position", "pageposition", "image_align", "imagealign",
            "image_position", "imageposition", "viewer_position", "viewerposition", "hpos"
        ]).trimmed.lowercased()
        switch raw {
        case "start", "leading", "begin", "beginning":
            return "left"
        case "end", "trailing":
            return "right"
        case "middle":
            return "center"
        default:
            return allowed(raw, values: ["left", "center", "right"], defaultValue: "center")
        }
    }

    private static func sortValue(_ query: [String: String]) -> (sort: String, descending: Bool) {
        let raw = firstQueryValue(query, keys: ["sort", "sort_by", "sortby", "order_by", "orderby", "order", "file_order", "fileorder", "filename_sort", "filenamesort"]).trimmed.lowercased()
        let descending = raw.hasPrefix("-")
        let value = descending ? String(raw.dropFirst()) : raw
        if ["asc", "ascending", "desc", "descending", "reverse", "reversed", "up", "down"].contains(value) {
            return ("path", descending)
        }
        switch value {
        case "", "path", "default", "original", "index", "idx":
            return ("path", descending)
        case "name", "filename", "file", "title":
            return ("name", descending)
        case "date", "time", "mtime", "modified":
            return ("date", descending)
        case "size", "bytes":
            return ("size", descending)
        case "type", "ext", "extension":
            return ("type", descending)
        default:
            return ("path", descending)
        }
    }

    private static func descendingValue(_ query: [String: String]) -> Bool {
        let order = firstQueryValue(query, keys: ["order"]).trimmed.lowercased()
        if ["desc", "descending", "reverse", "reversed", "down"].contains(order) {
            return true
        }
        let direction = firstQueryValue(query, keys: ["sort_order", "sortorder", "sort_dir", "sortdir", "sort_direction", "sortdirection", "order_direction", "orderdirection"]).trimmed.lowercased()
        if ["desc", "descending", "reverse", "reversed", "down"].contains(direction) {
            return true
        }
        return truthy(firstPresentQueryValue(query, keys: ["reverse"])) ||
            truthy(firstPresentQueryValue(query, keys: ["reversed"])) ||
            truthy(firstPresentQueryValue(query, keys: ["rev"])) ||
            truthy(firstPresentQueryValue(query, keys: ["desc"])) ||
            truthy(firstPresentQueryValue(query, keys: ["sort_reverse", "sortreverse"])) ||
            truthy(firstPresentQueryValue(query, keys: ["reverse_sort", "reversesort"])) ||
            truthy(firstPresentQueryValue(query, keys: ["reverse_order", "reverseorder"])) ||
            truthy(firstPresentQueryValue(query, keys: ["descending"]))
    }

    private static func lazyLoadingValue(_ query: [String: String]) -> Bool? {
        if let noLazy = firstPresentQueryValue(query, keys: ["no_lazy", "no-lazy", "nolazy"]), !noLazy.isEmpty, truthy(noLazy) {
            return false
        }
        if let eager = firstPresentQueryValue(query, keys: ["eager", "eagerload", "eager_load", "eager-loading", "eager_loading", "preload", "autoload", "auto_load", "autoloader"]), !eager.isEmpty, truthy(eager) {
            return false
        }
        if let value = firstPresentQueryValue(query, keys: [
            "lazy", "lazyload", "lazy_load", "lazy-loading", "lazy_loading",
            "lazyimages", "lazy_images", "lazyimage", "lazy_image",
            "image_lazy", "imagelazy", "image_lazyload", "imagelazyload",
            "defer", "defer_images", "deferimages"
        ]), !value.isEmpty {
            return truthy(value)
        }
        return nil
    }

    private static func truthy(_ value: String?) -> Bool {
        guard let value = value?.trimmed.lowercased(), !value.isEmpty else { return false }
        return !["0", "false", "no", "off"].contains(value)
    }

    private static func firstQueryValue(_ query: [String: String], keys: [String]) -> String {
        for key in keys {
            if let value = query[key]?.trimmed, !value.isEmpty {
                return value
            }
            let normalizedKey = normalizedQueryKey(key)
            if let pair = query.first(where: { normalizedQueryKey($0.key) == normalizedKey }),
               !pair.value.trimmed.isEmpty {
                return pair.value.trimmed
            }
        }
        return ""
    }

    private static func firstPresentQueryValue(_ query: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = query[key] {
                return value.trimmed
            }
            let normalizedKey = normalizedQueryKey(key)
            if let pair = query.first(where: { normalizedQueryKey($0.key) == normalizedKey }) {
                return pair.value.trimmed
            }
        }
        return nil
    }

    private static func normalizedQueryKey(_ key: String) -> String {
        key.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0).lowercased() }
            .joined()
    }
}
