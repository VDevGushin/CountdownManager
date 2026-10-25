import CountdownManagerUI
import Foundation
import QuartzCore

func testMarsOpeningTurn() {
    precondition(marsOpeningTurnDuration == 12)
    for size in [CGSize(width: 24, height: 22), CGSize(width: 30, height: 24)] {
        for anchor in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.2, y: 0.8)] {
            let animation = makeMarsOpeningAnimation(size: size, anchorPoint: anchor)
            guard let values = animation.values as? [NSValue] else {
                preconditionFailure("The Mars turn must have native transform keyframes")
            }
            precondition(animation.keyPath == "transform" && animation.duration == 12)
            precondition(animation.repeatCount == 0 && !animation.autoreverses && animation.isRemovedOnCompletion)
            precondition(animation.calculationMode == .linear)
            let transforms = values.map(\.caTransform3DValue)
            precondition(transforms.count == 49)
            let center = CGPoint(x: size.width * (0.5 - anchor.x), y: size.height * (0.5 - anchor.y))
            for (index, pose) in transforms.enumerated() {
                let phase = CGFloat(index) / CGFloat(transforms.count - 1) * 2 * .pi
                precondition(abs(pose.m11 - cos(phase)) < 0.00001 && abs(pose.m12 - sin(phase)) < 0.00001,
                             "The native frames must advance evenly through a full circle")
                let transformedX = center.x * pose.m11 + center.y * pose.m21 + pose.m41
                let transformedY = center.x * pose.m12 + center.y * pose.m22 + pose.m42
                precondition(abs(transformedX - center.x) < 0.00001 && abs(transformedY - center.y) < 0.00001,
                             "The planet must rotate around its center without drifting")
            }
        }
    }
    print("PASS Mars opening turn: finite slow full circle, fixed center, linear phases and no repetition")
}

@MainActor
func testMarsOpeningLifecycle() {
    // Unhosted layers discard animations on an async transaction commit.
    // Deadline/cancellation timing is checked on the real status-button layer.
    let opening = MarsOpeningAnimation()
    let layer = CALayer()
    layer.bounds = CGRect(x: 0, y: 0, width: 24, height: 22)
    let unrelated = CABasicAnimation(keyPath: "opacity")
    unrelated.duration = 30
    layer.add(unrelated, forKey: "unrelated-animation")
    precondition(!opening.isRunning)
    opening.start(layer: layer, statusShowsMars: true, reduceMotion: false)
    precondition(opening.isRunning && layer.animation(forKey: marsOpeningRotationKey) != nil)
    opening.start(layer: layer, statusShowsMars: true, reduceMotion: false)
    precondition(opening.isRunning && layer.animationKeys()?.filter { $0 == marsOpeningRotationKey }.count == 1,
                 "Repeated opening must replace the turn rather than stack animations")
    opening.stop()
    precondition(!opening.isRunning && layer.animation(forKey: marsOpeningRotationKey) == nil)
    precondition(layer.animation(forKey: "unrelated-animation") != nil,
                 "Stopping Mars must preserve other status animations")
    opening.stop()
    opening.start(layer: layer, statusShowsMars: true, reduceMotion: false)
    opening.start(layer: layer, statusShowsMars: true, reduceMotion: true)
    precondition(!opening.isRunning && layer.animation(forKey: marsOpeningRotationKey) == nil,
                 "Reduced motion must cancel the prior turn and must not start another")
    opening.start(layer: layer, statusShowsMars: false, reduceMotion: false)
    precondition(!opening.isRunning, "Favorite and timer representations must never rotate as Mars")
    opening.start(layer: nil, statusShowsMars: true, reduceMotion: false)
    precondition(!opening.isRunning, "An unavailable status surface cannot animate")
    opening.stop()
    print("PASS Mars opening lifecycle: real layer start/restart/stop, other animation preservation and reduced motion")
}
