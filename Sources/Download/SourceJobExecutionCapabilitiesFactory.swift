import Foundation

@MainActor
protocol SourceJobExecutionCapabilityProviding: AnyObject {
    func sourceJobRequestOptions(
        for url: URL
    ) -> HTTPRequestOptions

    func sourceJobResolverOptions(
        forJobAt jobIndex: Int
    ) -> SourceResolverExecutionOptions

    func sourceJobResolverContext(
        forJobAt jobIndex: Int
    ) -> SourceResolverExecutionContext

    func sourceJobAria2CanResolve(_ url: URL) -> Bool

    func sourceJobRetiredHTTPMessage(
        for url: URL
    ) -> String?

    func sourceJobPythonPlugin(
        for url: URL
    ) -> PythonSourceExecutionMatch?

    func sourceJobCustomCommandRule(
        for url: URL
    ) -> SiteRule?

    func canResolveSourceJobWithYTDLP(_ url: URL) -> Bool

    func sourceJobGenericPageCanResolve(_ url: URL) -> Bool
}

@MainActor
final class SourceJobExecutionCapabilitiesFactory {
    func makeCapabilities(
        forJobAt jobIndex: Int,
        provider: any SourceJobExecutionCapabilityProviding
    ) -> SourceJobExecutionCapabilities {
        SourceJobExecutionCapabilities(
            requestOptions: { url in
                provider.sourceJobRequestOptions(for: url)
            },
            resolverOptions: {
                provider.sourceJobResolverOptions(
                    forJobAt: jobIndex
                )
            },
            resolverContext: {
                provider.sourceJobResolverContext(
                    forJobAt: jobIndex
                )
            },
            aria2CanResolve: { url in
                provider.sourceJobAria2CanResolve(url)
            },
            retiredHTTPMessage: { url in
                provider.sourceJobRetiredHTTPMessage(for: url)
            },
            pythonPlugin: { url in
                provider.sourceJobPythonPlugin(for: url)
            },
            customCommandRule: { url in
                provider.sourceJobCustomCommandRule(for: url)
            },
            ytDLPCanResolve: { url in
                provider.canResolveSourceJobWithYTDLP(url)
            },
            genericPageCanResolve: { url in
                provider.sourceJobGenericPageCanResolve(url)
            }
        )
    }
}
