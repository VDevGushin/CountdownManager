import Foundation

/// Pure scheduling rules; mutable source state belongs exclusively to WeatherController.
package enum WeatherRequestPolicy {
    private static let origin = ContinuousClock.now
    package static func continuousSeconds() -> TimeInterval {
        let duration = origin.duration(to: ContinuousClock.now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    package enum Outcome: String, Sendable { case success, expired, temporary, overloaded, permanent, cancelled }
    package struct SourceState {
        package init() {}
        package var starts: [TimeInterval] = []
        package var fastUsed = 0
        package var slowFailures = 0
        package var expiredResponses = 0
        package var serverNotBefore: TimeInterval = 0
        package var providerCooldown: TimeInterval = 0
        package var lastStart: TimeInterval?
        package var quiescent = false
        package var attemptIndex = 0

        package mutating func start(at now: TimeInterval) {
            if quiescent, let lastStart, now - lastStart >= 1_800 { fastUsed = 0; slowFailures = 0; expiredResponses = 0 }
            quiescent = false
            starts.removeAll { now - $0 >= 600 }
            starts.append(now)
            attemptIndex = min(999, attemptIndex + 1)
            self.lastStart = now
        }
        package func admission(at now: TimeInterval) -> TimeInterval {
            let recent = starts.filter { now - $0 < 600 }
            return max(serverNotBefore, providerCooldown, recent.count >= 6 ? (recent.first ?? now) + 600 : now)
        }
    }

    package static func deadline(
        outcome: Outcome, remaining: TimeInterval = 0, usableSuccess: Bool = false,
        fastAllowed: Bool = false, now: TimeInterval, jitter: Double, state: inout SourceState
    ) -> TimeInterval? {
        let fraction = jitter.isFinite ? min(1, max(0, jitter)) : 0
        func interval(_ low: Double, _ high: Double) -> Double { low + (high - low) * fraction }
        func slow() -> Double {
            let ranges: [(Double, Double)] = [(300, 360), (900, 1_080), (1_800, 2_160)]
            let range = ranges[min(state.slowFailures, 2)]
            state.slowFailures = min(state.slowFailures + 1, 3)
            return interval(range.0, range.1)
        }
        let delay: TimeInterval
        switch outcome {
        case .cancelled: return nil
        case .success:
            if usableSuccess { state.fastUsed = 0; state.slowFailures = 0 }
            state.expiredResponses = 0
            delay = remaining >= 1_800 ? remaining : max(60, remaining) + interval(0, 15)
        case .expired:
            delay = state.expiredResponses == 0 ? interval(60, 90) : slow()
            state.expiredResponses = min(state.expiredResponses + 1, 3)
        case .temporary:
            if fastAllowed && state.fastUsed < 2 {
                delay = state.fastUsed == 0 ? interval(10, 20) : interval(45, 75)
                state.fastUsed += 1
            } else { delay = slow() }
        case .overloaded:
            delay = slow()
            state.providerCooldown = max(state.providerCooldown, now + delay)
        case .permanent: delay = interval(1_800, 2_160)
        }
        return max(now + delay, state.admission(at: now))
    }

    package static func classify(_ error: Error) -> Outcome {
        if error is CancellationError { return .cancelled }
        if let transport = error as? WeatherTransportFailure {
            let status: Int
            switch transport {
            case let .http(code, _), let .httpMetadata(code, _): status = code
            case .notModified, .validated: return .expired
            }
            if status == 429 || status == 503 { return .overloaded }
            if status == 408 || (500...599).contains(status) { return .temporary }
            return .permanent
        }
        let native = error as NSError
        guard native.domain == NSURLErrorDomain else { return .permanent }
        switch native.code {
        case NSURLErrorCancelled: return .cancelled
        case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed,
             NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorNotConnectedToInternet:
            return .temporary
        default: return .permanent
        }
    }
}
