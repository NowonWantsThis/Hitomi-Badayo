import Foundation

struct PythonSourceExecutionMatch {
    let plugin: PythonScriptPlugin
    let downloader: PythonDownloaderDescriptor
}

enum SourceExecutionRoute {
    case audioExtraction
    case aria2
    case pawchive(SourceResolverExecutionPlan)
    case pythonPlugin(PythonSourceExecutionMatch)
    case builtIn(SourceResolverExecutionPlan)
    case customCommand(SiteRule)
    case ytDLP
    case genericPage
    case direct
}

@MainActor
final class SourceExecutionRoutingService {
    let registry: SourceResolverRegistry
    let executor: SourceResolverExecutor

    init(
        registry: SourceResolverRegistry,
        executor: SourceResolverExecutor
    ) {
        precondition(
            executor.registry === registry,
            "SourceResolverExecutor must use the routing service's registry."
        )
        self.registry = registry
        self.executor = executor
    }

    func route(
        for url: URL,
        headers: HTTPRequestOptions,
        options: SourceResolverExecutionOptions,
        context: SourceResolverExecutionContext,
        pawchiveSiteAddresses: [String],
        isAudioExtractionRequest: Bool,
        aria2CanResolve: () -> Bool,
        pythonPluginAllowed: Bool,
        pythonPlugin: () -> PythonSourceExecutionMatch?,
        customCommandRule: () -> SiteRule?,
        ytDLPCanResolve: () -> Bool,
        genericPageCanResolve: () -> Bool
    ) throws -> SourceExecutionRoute {
        if isAudioExtractionRequest {
            return .audioExtraction
        }
        if aria2CanResolve() {
            return .aria2
        }
        if registry.matchesPawchive(
            url,
            siteAddresses: pawchiveSiteAddresses
        ) {
            guard let plan = executor.executionPlan(
                for: .pawchive,
                url: url,
                headers: headers,
                options: options
            ) else {
                throw NativeDownloadError.unsupported(
                    "Pawchive execution settings are unavailable."
                )
            }
            return .pawchive(plan)
        }
        if pythonPluginAllowed, let match = pythonPlugin() {
            return .pythonPlugin(match)
        }
        if let route = registry.firstMatchingStandardRoute(for: url),
           let plan = executor.executionPlan(
               for: route,
               url: url,
               headers: headers,
               options: options,
               context: context
           ) {
            return .builtIn(plan)
        }
        if let rule = customCommandRule() {
            return .customCommand(rule)
        }
        if ytDLPCanResolve() {
            return .ytDLP
        }
        if genericPageCanResolve() {
            return .genericPage
        }
        return .direct
    }
}
