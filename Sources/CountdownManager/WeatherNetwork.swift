import Foundation
import Network

package struct WeatherNetworkState: Equatable, Sendable {
    package enum Status: Equatable, Sendable { case unknown, satisfied, offline }
    package var status: Status
    package var expensive: Bool
    package var constrained: Bool
    package init(status: Status = .unknown, expensive: Bool = false, constrained: Bool = false) {
        self.status = status; self.expensive = expensive; self.constrained = constrained
    }
}

@MainActor
package protocol WeatherNetworkMonitoring: AnyObject {
    func start(_ update: @escaping @MainActor @Sendable (WeatherNetworkState) -> Void)
    func stop()
}

/// A lifecycle-bound signal source, not an HTTP reachability test or cache owner.
@MainActor
final class NativeWeatherNetworkMonitor: WeatherNetworkMonitoring {
    private var monitor: NWPathMonitor?
    private var revision = 0
    private let queue = DispatchQueue(label: "local.countdownmanager.weather-path", qos: .utility)

    func start(_ update: @escaping @MainActor @Sendable (WeatherNetworkState) -> Void) {
        guard monitor == nil else { return }
        revision += 1
        let expected = revision
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let status: WeatherNetworkState.Status = path.status == .satisfied ? .satisfied : (path.status == .unsatisfied ? .offline : .unknown)
            let state = WeatherNetworkState(status: status,
                                            expensive: path.isExpensive, constrained: path.isConstrained)
            Task { @MainActor in
                guard let self, self.monitor != nil, self.revision == expected else { return }
                update(state)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        revision += 1
        monitor?.cancel()
        monitor = nil
    }
}
