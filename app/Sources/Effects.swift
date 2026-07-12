import SwiftUI
import MygrationCore

/// Ambient, Apple-esque backdrop — slow-drifting color blobs behind everything.
struct AuroraBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.addFilter(.blur(radius: 80))
                for (i, c) in [Color.blue, .purple, .teal, .indigo].enumerated() {
                    let x = size.width  * (0.5 + 0.35 * cos(t * 0.1 + Double(i) * 1.7))
                    let y = size.height * (0.5 + 0.35 * sin(t * 0.13 + Double(i) * 2.1))
                    let r: CGFloat = 180
                    ctx.fill(Path(ellipseIn: CGRect(x: x-r, y: y-r, width: r*2, height: r*2)),
                             with: .color(c.opacity(0.35)))
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }
}

/// Concentric pulses radiating out — the "I'm advertising" heartbeat.
struct RadiatingWaves: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { i in
                    let phase = (t * 0.6 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(.tint.opacity(1 - phase), lineWidth: 2)
                        .frame(width: 60 + phase * 160, height: 60 + phase * 160)
                }
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 30)).foregroundStyle(.tint)
            }
            .frame(height: 220)
        }
    }
}

/// Full-window reaction to the pairing phase: connecting spinner, the
/// established → paired merge, and failure. This is the ceremony's climax.
struct PairingOverlay: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Group {
            switch model.session.phase {
            case .connecting:
                Glass { ProgressView("Opening secure channel…").padding() }
            case .established:
                Glass { Label("Verified — exchanging setup…", systemImage: "lock.shield")
                    .font(.title3).padding() }
            case .paired(let peer):
                PairedCard(peer: peer) { model.reset() }
            case .failed(let why):
                Glass {
                    VStack(spacing: 12) {
                        Image(systemName: "xmark.seal").font(.largeTitle).foregroundStyle(.red)
                        Text(why).multilineTextAlignment(.center)
                        Button("Try again") { model.reset() }.buttonStyle(.borderedProminent)
                    }.padding()
                }
            default: EmptyView()
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: model.session.phase)
    }
}

struct PairedCard: View {
    let peer: PeerInfo
    let done: () -> Void
    @State private var burst = false
    var body: some View {
        Glass {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(.green.opacity(0.2)).frame(width: 90, height: 90)
                        .scaleEffect(burst ? 1.15 : 0.8)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54)).foregroundStyle(.green)
                }
                Text("Paired with \(peer.name)").font(.title2.bold())
                Label("\(peer.arch)  ·  macOS \(peer.os)", systemImage: "cpu")
                    .foregroundStyle(.secondary)
                Text(archNote(mine: PeerInfo.mine().arch, theirs: peer.arch))
                    .font(.callout).foregroundStyle(.tint).multilineTextAlignment(.center)
                Button("Continue to plan") { done() }.buttonStyle(.borderedProminent)
            }.padding(30)
        }
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { burst = true } }
    }

    func archNote(mine: String, theirs: String) -> String {
        mine == theirs ? "Same architecture — a straight rebuild."
        : "\(theirs) → \(mine): apps reinstall natively, nothing x86 carried over."
    }
}

struct Glass<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12)))
            .shadow(radius: 30)
    }
}

// MARK: - menu bar

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mygration", systemImage: "arrow.triangle.2.circlepath").font(.headline)
            Text("Two Macs, one setup.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Start a migration…") { openWindow(id: "main") }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12).frame(width: 240)
    }
}
