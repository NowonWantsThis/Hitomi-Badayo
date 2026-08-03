import Foundation

protocol LocalAPIServing: AnyObject {
    func start() throws
    func stop()
}

extension LocalHTTPAPIServer: LocalAPIServing {}

final class LocalAPIServerCoordinator {
    typealias Handler = (
        LocalHTTPRequest
    ) async -> LocalHTTPResponse
    typealias ServerFactory = (
        UInt16,
        @escaping Handler
    ) -> LocalAPIServing

    private let serverFactory: ServerFactory
    private var server: LocalAPIServing?

    var isRunning: Bool {
        server != nil
    }

    init(
        serverFactory: @escaping ServerFactory = { port, handler in
            LocalHTTPAPIServer(port: port, handler: handler)
        }
    ) {
        self.serverFactory = serverFactory
    }

    func start(
        port: UInt16,
        handler: @escaping Handler
    ) throws {
        stop()
        let candidate = serverFactory(port, handler)
        do {
            try candidate.start()
            server = candidate
        } catch {
            candidate.stop()
            throw error
        }
    }

    func stop() {
        server?.stop()
        server = nil
    }
}
