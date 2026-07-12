import SwiftUI

/// Drives the NameDrop ripple (Ripple.metal) as a time-animated distortion
/// emanating from `origin`. Attach with `.rippleOnce(trigger:origin:)`.
struct RippleModifier: ViewModifier {
    var origin: CGPoint
    var elapsedTime: TimeInterval
    var duration: TimeInterval

    // wave shape — tuned to feel like the iOS 17 effect
    let amplitude: Double = 16
    let frequency: Double = 14
    let decay: Double = 8
    let speed: Double = 1400

    func body(content: Content) -> some View {
        let shader = ShaderLibrary.default.Ripple(
            .float2(origin.x, origin.y),
            .float(elapsedTime),
            .float(amplitude),
            .float(frequency),
            .float(decay),
            .float(speed)
        )
        content.visualEffect { view, _ in
            view.layerEffect(
                shader,
                maxSampleOffset: CGSize(width: amplitude, height: amplitude),
                isEnabled: 0 < elapsedTime && elapsedTime < duration)
        }
    }
}

extension View {
    /// Fire a single ripple from `origin` each time `trigger` changes.
    func rippleOnce(trigger: some Equatable, origin: CGPoint,
                    duration: TimeInterval = 1.4) -> some View {
        modifier(RippleTrigger(trigger: trigger, origin: origin, duration: duration))
    }
}

private struct RippleTrigger<T: Equatable>: ViewModifier {
    let trigger: T
    let origin: CGPoint
    let duration: TimeInterval
    @State private var start: Date?

    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let elapsed = start.map { timeline.date.timeIntervalSince($0) } ?? .infinity
            content.modifier(RippleModifier(origin: origin, elapsedTime: elapsed, duration: duration))
        }
        .onChange(of: trigger) { _, _ in start = Date() }
    }
}
