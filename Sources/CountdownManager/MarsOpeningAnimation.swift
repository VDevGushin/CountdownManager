import QuartzCore

package let marsOpeningRotationKey = "countdown.mars.opening-turn"
package let marsOpeningTurnDuration: TimeInterval = 12

package func makeMarsOpeningAnimation(size: CGSize, anchorPoint: CGPoint = .zero) -> CAKeyframeAnimation {
    let animation = CAKeyframeAnimation(keyPath: "transform")
    let center = CGPoint(x: size.width * (0.5 - anchorPoint.x), y: size.height * (0.5 - anchorPoint.y))
    // Small successive rotations retain the full turn; interpolating only the
    // equivalent start/end matrices would produce no visible movement.
    animation.values = (0...48).map { step in
        var transform = CATransform3DTranslate(CATransform3DIdentity, center.x, center.y, 0)
        transform = CATransform3DRotate(transform, CGFloat(step) / 48 * 2 * .pi, 0, 0, 1)
        return CATransform3DTranslate(transform, -center.x, -center.y, 0)
    }
    animation.duration = marsOpeningTurnDuration
    animation.calculationMode = .linear
    animation.timingFunction = CAMediaTimingFunction(name: .linear)
    animation.isRemovedOnCompletion = true
    return animation
}

@MainActor
package final class MarsOpeningAnimation {
    private weak var layer: CALayer?
    private var completionTask: Task<Void, Never>?

    package var isRunning: Bool { layer?.animation(forKey: marsOpeningRotationKey) != nil }

    package init() {}

    deinit { completionTask?.cancel() }

    package func start(layer: CALayer?, statusShowsMars: Bool, reduceMotion: Bool) {
        stop()
        guard statusShowsMars, !reduceMotion, let layer else { return }
        self.layer = layer
        layer.add(makeMarsOpeningAnimation(size: layer.bounds.size, anchorPoint: layer.anchorPoint),
                  forKey: marsOpeningRotationKey)
        // A status-button backing layer can retain its named CA animation after
        // the visible turn has finished. Release ownership at the same deadline.
        completionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(marsOpeningTurnDuration * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func updateEligibility(showsMars: Bool) {
        // Priority changes cancel this turn; returning to Mars later does not
        // restart it until another explicit opening.
        if !showsMars { stop() }
    }

    package func stop() {
        completionTask?.cancel()
        completionTask = nil
        layer?.removeAnimation(forKey: marsOpeningRotationKey)
        layer = nil
    }
}
