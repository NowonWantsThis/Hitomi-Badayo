import Foundation

struct SourceJobExecutionRequest {
    var source: String
    var directDownloadOverride: Bool
    var originalInputType: OriginalInputType?
    var testingResolvedDownloadAvailable: Bool
    var pawchiveSiteAddresses: [String]
    var isAudioExtractionRequest: Bool
    var pythonPluginAllowed: Bool
}

struct SourceJobExecutionCapabilities {
    var requestOptions: (URL) -> HTTPRequestOptions
    var resolverOptions: () -> SourceResolverExecutionOptions
    var resolverContext: () -> SourceResolverExecutionContext
    var aria2CanResolve: (URL) -> Bool
    var retiredHTTPMessage: (URL) -> String?
    var pythonPlugin: (URL) -> PythonSourceExecutionMatch?
    var customCommandRule: (URL) -> SiteRule?
    var ytDLPCanResolve: (URL) -> Bool
    var genericPageCanResolve: (URL) -> Bool
}

struct SourceJobExecutionActions {
    var input: SourceInputExecutionActions
    var source:
        (HTTPRequestOptions) -> SourceExecutionActions
}

@MainActor
protocol SourceJobExecuting: AnyObject {
    func execute(
        _ request: SourceJobExecutionRequest,
        capabilities: SourceJobExecutionCapabilities,
        actions: SourceJobExecutionActions
    ) async throws
}

@MainActor
final class SourceJobExecutionService: SourceJobExecuting {
    let inputRoutingService: SourceInputRoutingService
    let inputExecutionDispatchService:
        SourceInputExecutionDispatchService
    let sourceRoutingService: SourceExecutionRoutingService
    let sourceExecutionDispatchService:
        SourceExecutionDispatchService

    init(
        inputRoutingService:
            SourceInputRoutingService = SourceInputRoutingService(),
        inputExecutionDispatchService:
            SourceInputExecutionDispatchService,
        sourceRoutingService: SourceExecutionRoutingService,
        sourceExecutionDispatchService:
            SourceExecutionDispatchService
    ) {
        self.inputRoutingService = inputRoutingService
        self.inputExecutionDispatchService =
            inputExecutionDispatchService
        self.sourceRoutingService = sourceRoutingService
        self.sourceExecutionDispatchService =
            sourceExecutionDispatchService
    }

    func execute(
        _ request: SourceJobExecutionRequest,
        capabilities: SourceJobExecutionCapabilities,
        actions: SourceJobExecutionActions
    ) async throws {
        let inputRoute = try inputRoutingService.route(
            source: request.source,
            directDownloadOverride:
                request.directDownloadOverride,
            originalInputType: request.originalInputType,
            testingResolvedDownloadAvailable:
                request.testingResolvedDownloadAvailable,
            aria2CanResolve: capabilities.aria2CanResolve,
            retiredHTTPMessage:
                capabilities.retiredHTTPMessage
        )

        let inputResult =
            try await inputExecutionDispatchService.execute(
                inputRoute,
                actions: actions.input
            )
        guard case .web(let url) = inputResult else {
            return
        }

        let headers = capabilities.requestOptions(url)
        let resolverOptions = capabilities.resolverOptions()
        let resolverContext = capabilities.resolverContext()
        let executionRoute = try sourceRoutingService.route(
            for: url,
            headers: headers,
            options: resolverOptions,
            context: resolverContext,
            pawchiveSiteAddresses:
                request.pawchiveSiteAddresses,
            isAudioExtractionRequest:
                request.isAudioExtractionRequest,
            aria2CanResolve: {
                capabilities.aria2CanResolve(url)
            },
            pythonPluginAllowed:
                request.pythonPluginAllowed,
            pythonPlugin: {
                capabilities.pythonPlugin(url)
            },
            customCommandRule: {
                capabilities.customCommandRule(url)
            },
            ytDLPCanResolve: {
                capabilities.ytDLPCanResolve(url)
            },
            genericPageCanResolve: {
                capabilities.genericPageCanResolve(url)
            }
        )

        try await sourceExecutionDispatchService.execute(
            executionRoute,
            url: url,
            actions: actions.source(headers)
        )
    }
}
