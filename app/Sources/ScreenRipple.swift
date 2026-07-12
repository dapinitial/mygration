import SwiftUI
import AppKit

/// Plays a full-screen NameDrop light-wash across every display: a transparent,
/// click-through overlay window at screen-saver level that renders the
/// ScreenRipple shader, then dismisses itself. Use `ScreenRipple.flash()`.
@MainActor
final class ScreenRippleController {
    static let shared = ScreenRippleController()
    private var windows: [NSWindow] = []

    /// Flash the ripple on all screens. `origin` is in the main screen's
    /// top-left points; nil = center of each screen.
    func flash(duration: TimeInterval = 1.7) {
        dismiss()
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let size = screen.frame.size
            let view = ScreenRippleView(size: size,
                                        origin: CGPoint(x: size.width/2, y: size.height/2),
                                        duration: duration) { [weak self] in self?.dismiss() }
            w.contentView = NSHostingView(rootView: view)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func dismiss() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

struct ScreenRippleView: View {
    let size: CGSize
    let origin: CGPoint
    let duration: TimeInterval
    let onDone: () -> Void
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Rectangle()
                .fill(.white)   // colorEffect overrides per-pixel; fill is irrelevant
                .colorEffect(ShaderLibrary.default.ScreenRipple(
                    .float2(Float(size.width), Float(size.height)),
                    .float2(Float(origin.x), Float(origin.y)),
                    .float(elapsed),
                    .float(duration)))
                .ignoresSafeArea()
                .onChange(of: elapsed >= duration) { _, finished in
                    if finished { onDone() }
                }
        }
    }
}
