import Foundation

@MainActor
protocol RefreshScheduling {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class RefreshScheduler: RefreshScheduling {
    private var timer: Timer?

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            // This timer is attached only to the main run loop; avoid another queued hop.
            MainActor.assumeIsolated {
                self?.timer = nil
                action()
            }
        }
        timer.tolerance = EnergyPolicy.timerTolerance(interval: delay)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
