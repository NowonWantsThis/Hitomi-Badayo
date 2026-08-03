import Foundation

@MainActor
final class ClipboardMonitorCoordinator {
    typealias Tick =
        @MainActor () -> Void
    typealias TimerFactory =
        @MainActor (
            TimeInterval,
            @escaping @Sendable () -> Void
        ) -> Timer
    typealias TimerInstaller =
        @MainActor (Timer) -> Void

    private let makeTimer: TimerFactory
    private let installTimer: TimerInstaller
    private var timer: Timer?

    init(
        makeTimer:
            @escaping TimerFactory = {
                interval,
                fire in
                Timer(
                    timeInterval: interval,
                    repeats: true
                ) { _ in
                    fire()
                }
            },
        installTimer:
            @escaping TimerInstaller = {
                RunLoop.main.add(
                    $0,
                    forMode: .common
                )
            }
    ) {
        self.makeTimer = makeTimer
        self.installTimer = installTimer
    }

    var isRunning: Bool {
        timer != nil
    }

    func start(
        interval: TimeInterval = 1,
        tick:
            @escaping Tick
    ) {
        stop()
        let timer = makeTimer(
            interval
        ) {
            Task { @MainActor in
                tick()
            }
        }
        installTimer(timer)
        self.timer = timer
    }

    @discardableResult
    func stop() -> Bool {
        guard let timer else {
            return false
        }
        self.timer = nil
        timer.invalidate()
        return true
    }

    deinit {
        timer?.invalidate()
    }
}
