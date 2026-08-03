import Foundation

struct SiteRulePluginManifest: Decodable {
    var name: String?
    var environment: [String: String]
    var options: [String: String]
    var workingDirectory: String?
    var rules: [SiteRulePluginRule]

    private enum CodingKeys: String, CodingKey {
        case name
        case pluginName
        case title
        case label
        case environment
        case env
        case variables
        case options
        case settings
        case config
        case preferences
        case workingDirectory
        case working_directory
        case workingDirectoryTemplate
        case working_directory_template
        case cwd
        case workdir
        case workingDir
        case currentDirectory
        case current_directory
        case rules
        case siteRules
        case site_rules
        case scripts
        case scriptRules
        case script_rules
        case extractors
        case downloaders
        case commands
        case handlers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = Self.string(in: container, keys: [.name, .pluginName, .title, .label])
        environment = Self.stringDictionary(in: container, keys: [.environment, .env, .variables])
        options = Self.stringDictionary(in: container, keys: [.options, .settings, .config, .preferences])
        workingDirectory = Self.string(
            in: container,
            keys: [
                .workingDirectory,
                .working_directory,
                .workingDirectoryTemplate,
                .working_directory_template,
                .cwd,
                .workdir,
                .workingDir,
                .currentDirectory,
                .current_directory
            ]
        )
        for key in Self.ruleListKeys {
            if let rules = try container.decodeIfPresent([SiteRulePluginRule].self, forKey: key) {
                self.rules = rules
                return
            }
        }
        rules = try container.decode([SiteRulePluginRule].self, forKey: .siteRules)
    }

    func siteRules(sourceURL: URL? = nil) -> [SiteRule] {
        let sourceEnvironment = Self.sourceEnvironment(for: sourceURL)
        return rules.compactMap {
            $0.siteRule(
                pluginName: name,
                manifestEnvironment: sourceEnvironment.merging(environment) { _, manifestValue in manifestValue },
                manifestOptions: options,
                manifestWorkingDirectory: workingDirectory,
                sourceURL: sourceURL
            )
        }
    }

    private static func sourceEnvironment(for sourceURL: URL?) -> [String: String] {
        guard let sourceURL else { return [:] }
        return [
            "HITOMI_NATIVE_PLUGIN_MANIFEST": sourceURL.path,
            "HITOMI_NATIVE_PLUGIN_MANIFEST_DIR": sourceURL.deletingLastPathComponent().path
        ]
    }

    private static func stringDictionary(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> [String: String] {
        for key in keys {
            if let value = try? container.decodeIfPresent([String: String].self, forKey: key) {
                return DownloadMetadata.clean(value)
            }
            if let object = try? container.decodeIfPresent([String: SiteRulePluginOptionValue].self, forKey: key) {
                return DownloadMetadata.clean(object.mapValues(\.stringValue))
            }
        }
        return [:]
    }

    private static func string(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    private static var ruleListKeys: [CodingKeys] {
        [
            .rules,
            .siteRules,
            .site_rules,
            .scripts,
            .scriptRules,
            .script_rules,
            .extractors,
            .downloaders,
            .commands,
            .handlers
        ]
    }
}

enum SiteRulePluginOptionValue: Decodable {
    case string(String)
    case bool(Bool)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string("")
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            if value.rounded(.towardZero) == value {
                return String(Int64(value))
            }
            return String(value)
        }
    }
}

struct SiteRulePluginRule: Decodable {
    var id: UUID?
    var name: String?
    var host: String?
    var hostSuffix: String?
    var domain: String?
    var matchURL: String?
    var urlPattern: String?
    var pattern: String?
    var pathPattern: String?
    var handler: SiteRuleHandler?
    var command: String?
    var commandTemplate: String?
    var referer: String?
    var refererTemplate: String?
    var userAgent: String?
    var environment: [String: String] = [:]
    var options: [String: String] = [:]
    var workingDirectory: String?
    var workingDirectoryTemplate: String?
    var archiveMode: SiteArchiveMode?
    var deleteOriginalAfterArchiving: Bool?
    var isEnabled: Bool?
    var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case title
        case label
        case host
        case hostname
        case site
        case hostSuffix
        case host_suffix
        case matchHost
        case match_host
        case domain
        case baseURL
        case base_url
        case url
        case match
        case urlMatch
        case url_match
        case matchURL
        case match_url
        case urlPattern
        case url_pattern
        case pattern
        case pathPattern
        case path_pattern
        case path
        case handler
        case type
        case engine
        case downloader
        case mode
        case command
        case cmd
        case commandTemplate
        case command_template
        case commandLine
        case command_line
        case script
        case scriptPath
        case script_path
        case executable
        case run
        case referer
        case referrer
        case refererTemplate
        case referer_template
        case referrerTemplate
        case referrer_template
        case userAgent
        case user_agent
        case userAgentHeader = "user-agent"
        case ua
        case headers
        case requestHeaders
        case request_headers
        case httpHeaders
        case http_headers
        case environment
        case env
        case variables
        case options
        case settings
        case config
        case preferences
        case params
        case workingDirectory
        case working_directory
        case workingDirectoryTemplate
        case working_directory_template
        case cwd
        case workdir
        case workingDir
        case currentDirectory
        case current_directory
        case archiveMode
        case archive_mode
        case archive
        case packageMode
        case package_mode
        case package
        case deleteOriginalAfterArchiving
        case deleteOriginalAfterArchive
        case delete_original_after_archive
        case deleteOriginal
        case delete_original
        case isEnabled
        case enabled
        case enable
        case disabled
        case createdAt
        case created_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(UUID.self, forKey: .id)
        name = Self.string(in: container, keys: [.name, .title, .label])
        host = Self.string(in: container, keys: [.host, .hostname, .site])
        hostSuffix = Self.string(in: container, keys: [.hostSuffix, .host_suffix, .matchHost, .match_host])
        domain = Self.string(in: container, keys: [.domain, .baseURL, .base_url])
        matchURL = Self.string(in: container, keys: [.url, .match, .urlMatch, .url_match, .matchURL, .match_url])
        if host == nil, hostSuffix == nil, domain == nil, let matchURLHost = Self.host(fromMatchURL: matchURL) {
            host = matchURLHost
        }
        urlPattern = Self.string(in: container, keys: [.urlPattern, .url_pattern])
        pattern = Self.string(in: container, keys: [.pattern, .match])
        pathPattern = Self.string(in: container, keys: [.pathPattern, .path_pattern, .path])
        handler = Self.handler(in: container, keys: [.handler, .type, .engine, .downloader, .mode])
        command = Self.string(in: container, keys: [.command, .cmd, .commandLine, .command_line, .script, .scriptPath, .script_path, .executable, .run])
        commandTemplate = Self.string(in: container, keys: [.commandTemplate, .command_template])
        let headerOverrides = Self.stringDictionary(in: container, keys: [.headers, .requestHeaders, .request_headers, .httpHeaders, .http_headers])
        referer = Self.string(in: container, keys: [.referer, .referrer])
            ?? Self.headerValue(in: headerOverrides, names: ["referer", "referrer"])
        refererTemplate = Self.string(in: container, keys: [.refererTemplate, .referer_template, .referrerTemplate, .referrer_template])
        userAgent = Self.string(in: container, keys: [.userAgent, .user_agent, .userAgentHeader, .ua])
            ?? Self.headerValue(in: headerOverrides, names: ["user-agent", "user_agent", "useragent", "ua"])
        environment = Self.stringDictionary(in: container, keys: [.environment, .env, .variables])
        options = Self.stringDictionary(in: container, keys: [.options, .settings, .config, .preferences, .params])
        workingDirectory = Self.string(in: container, keys: [.workingDirectory, .working_directory, .cwd, .workdir, .workingDir, .currentDirectory, .current_directory])
        workingDirectoryTemplate = Self.string(in: container, keys: [.workingDirectoryTemplate, .working_directory_template])
        archiveMode = Self.archiveMode(in: container, keys: [.archiveMode, .archive_mode, .archive, .packageMode, .package_mode, .package])
        deleteOriginalAfterArchiving = Self.bool(
            in: container,
            keys: [.deleteOriginalAfterArchiving, .deleteOriginalAfterArchive, .delete_original_after_archive, .deleteOriginal, .delete_original]
        )
        if let disabled = Self.bool(in: container, keys: [.disabled]) {
            isEnabled = !disabled
        } else {
            isEnabled = Self.bool(in: container, keys: [.isEnabled, .enabled, .enable])
        }
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ??
            (try? container.decodeIfPresent(Date.self, forKey: .created_at))
    }

    func siteRule(
        pluginName: String?,
        manifestEnvironment: [String: String] = [:],
        manifestOptions: [String: String] = [:],
        manifestWorkingDirectory: String? = nil,
        sourceURL: URL? = nil
    ) -> SiteRule? {
        let normalizedHost = SiteRule.normalizedHostSuffix(hostSuffix ?? host ?? domain ?? "")
        guard !normalizedHost.isEmpty else { return nil }

        let normalizedPattern = SiteRule.normalizedURLPattern(urlPattern ?? pathPattern ?? pattern ?? matchURL)
        let rawCommandValue = (commandTemplate ?? command)?.trimmed ?? ""
        let commandValue = Self.resolvedCommandTemplate(rawCommandValue, sourceURL: sourceURL)
        guard commandValue.isEmpty || commandValue.contains("{url}") else { return nil }

        let refererValue = (refererTemplate ?? referer)?.trimmed ?? ""
        let userAgentValue = userAgent?.trimmed ?? ""
        let workingDirectoryValue = Self.resolvedRelativePathTemplate(
            (workingDirectoryTemplate ?? workingDirectory ?? manifestWorkingDirectory)?.trimmed ?? "",
            sourceURL: sourceURL
        )
        let hasHeaderOverrides = !refererValue.isEmpty || !userAgentValue.isEmpty
        let resolvedHandler: SiteRuleHandler
        if !commandValue.isEmpty {
            resolvedHandler = .customCommand
        } else if handler == .ytdlp {
            resolvedHandler = .ytdlp
        } else if hasHeaderOverrides {
            resolvedHandler = .headers
        } else {
            resolvedHandler = .ytdlp
        }

        let fallbackName = [pluginName?.trimmed, normalizedHost]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")

        return SiteRule(
            id: id ?? UUID(),
            name: (name?.trimmed.isEmpty ?? true) ? fallbackName : name!.trimmed,
            hostSuffix: normalizedHost,
            urlPattern: normalizedPattern,
            handler: resolvedHandler,
            commandTemplate: commandValue.isEmpty ? nil : commandValue,
            refererTemplate: refererValue.isEmpty ? nil : refererValue,
            userAgent: userAgentValue.isEmpty ? nil : userAgentValue,
            environment: manifestEnvironment.merging(environment) { _, ruleValue in ruleValue },
            options: manifestOptions.merging(options) { _, ruleValue in ruleValue },
            workingDirectoryTemplate: workingDirectoryValue.isEmpty ? nil : workingDirectoryValue,
            archiveMode: archiveMode ?? .default,
            deleteOriginalAfterArchiving: deleteOriginalAfterArchiving ?? false,
            isEnabled: isEnabled ?? true,
            createdAt: createdAt ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func string(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    private static func bool(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Bool? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                switch value.trimmed.lowercased() {
                case "1", "true", "yes", "y", "on":
                    return true
                case "0", "false", "no", "n", "off":
                    return false
                default:
                    break
                }
            }
        }
        return nil
    }

    private static func stringDictionary(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> [String: String] {
        for key in keys {
            if let value = try? container.decodeIfPresent([String: String].self, forKey: key) {
                return DownloadMetadata.clean(value)
            }
            if let object = try? container.decodeIfPresent([String: SiteRulePluginOptionValue].self, forKey: key) {
                return DownloadMetadata.clean(object.mapValues(\.stringValue))
            }
        }
        return [:]
    }

    private static func headerValue(in headers: [String: String], names: [String]) -> String? {
        for name in names {
            if let value = headers[name], !value.trimmed.isEmpty {
                return value
            }
            if let value = headers.first(where: { $0.key.lowercased() == name })?.value,
               !value.trimmed.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func host(fromMatchURL raw: String?) -> String? {
        guard let raw = raw?.trimmed,
              !raw.isEmpty,
              let url = URL(string: raw),
              let host = url.host?.trimmed,
              !host.isEmpty else {
            return nil
        }
        return host
    }

    private static func resolvedCommandTemplate(_ template: String, sourceURL: URL?) -> String {
        guard let sourceURL,
              !template.isEmpty,
              let commandRange = commandTokenRange(in: template) else {
            return template
        }

        let rawCommand = String(template[commandRange])
        let expandedCommand = (rawCommand as NSString).expandingTildeInPath
        guard rawCommand.contains("/"),
              !rawCommand.hasPrefix("/"),
              !rawCommand.hasPrefix("~"),
              URL(string: expandedCommand)?.scheme == nil else {
            return template
        }

        let resolvedCommand = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(rawCommand)
            .standardizedFileURL
            .path
        var resolved = template
        resolved.replaceSubrange(commandRange, with: resolvedCommand)
        return resolved
    }

    private static func resolvedRelativePathTemplate(_ template: String, sourceURL: URL?) -> String {
        let trimmed = template.trimmed
        guard let sourceURL, !trimmed.isEmpty else { return trimmed }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              URL(string: expanded)?.scheme == nil else {
            return trimmed
        }
        return sourceURL.deletingLastPathComponent()
            .appendingPathComponent(trimmed)
            .standardizedFileURL
            .path
    }

    private static func commandTokenRange(in template: String) -> Range<String.Index>? {
        var start = template.startIndex
        while start < template.endIndex, isCommandWhitespace(template[start]) {
            start = template.index(after: start)
        }
        guard start < template.endIndex else { return nil }

        let quote: Character?
        if template[start] == "\"" || template[start] == "'" {
            quote = template[start]
            start = template.index(after: start)
        } else {
            quote = nil
        }

        var end = start
        while end < template.endIndex {
            let character = template[end]
            if let quote {
                if character == quote { break }
            } else if isCommandWhitespace(character) {
                break
            }
            end = template.index(after: end)
        }

        return start < end ? start..<end : nil
    }

    private static func isCommandWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func handler(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> SiteRuleHandler? {
        guard let value = string(in: container, keys: keys)?.trimmed.lowercased(), !value.isEmpty else { return nil }
        switch value {
        case SiteRuleHandler.ytdlp.rawValue, "ytdlp", "youtube-dl", "youtube_dl":
            return .ytdlp
        case SiteRuleHandler.customCommand.rawValue, "custom", "custom-command", "custom_command", "customcommand",
             "command-line", "command_line", "external", "exec", "executable", "script", "shell", "python":
            return .customCommand
        case SiteRuleHandler.headers.rawValue, "header", "request-headers", "request_headers", "http-headers", "http_headers", "headers-only", "headers_only":
            return .headers
        default:
            return SiteRuleHandler(rawValue: value)
        }
    }

    private static func archiveMode(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> SiteArchiveMode? {
        guard let value = string(in: container, keys: keys)?.trimmed.lowercased(), !value.isEmpty else { return nil }
        switch value {
        case "default", "inherit":
            return .default
        case "zip":
            return .zip
        case "cbz":
            return .cbz
        case "none", "off", "disabled", "false":
            return SiteArchiveMode.none
        default:
            return SiteArchiveMode(rawValue: value)
        }
    }
}
