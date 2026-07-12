import SwiftUI
import MygrationCore
import Network

/// The migration window: choose a role, then either display a PIN (host) or
/// see nearby Macs as drifting bubbles you tap to pair (receiver). On success,
/// the two devices merge into a paired card — the NameDrop moment.
struct DiscoveryView: View {
    @EnvironmentObject var model: AppModel
    @State private var pairedTick = 0

    private var isPaired: Bool {
        if case .paired = model.session.phase { return true }; return false
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AuroraBackground()
                switch model.mode {
                case .choosing:  RolePicker()
                case .hosting:   HostView()
                case .joining:   ReceiverView()
                }
                PairingOverlay()   // reacts to session.phase across all modes
            }
            // the NameDrop water-ripple, fired from the window center at pairing
            .rippleOnce(trigger: pairedTick,
                        origin: CGPoint(x: geo.size.width/2, y: geo.size.height/2))
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: model.mode)
        .onChange(of: isPaired) { _, now in
            if now { pairedTick += 1; model.flashScreen() }   // window ripple + full-screen wash
        }
    }
}

// MARK: - role picker

struct RolePicker: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Image(systemName: "laptopcomputer.and.arrow.down")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                Text("Mygration").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Bring two Macs together").foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                RoleCard(title: "Send from this Mac", subtitle: "Show a PIN",
                         symbol: "arrow.up.forward.app") { model.beHost() }
                RoleCard(title: "Set up this Mac", subtitle: "Find a nearby Mac",
                         symbol: "sparkles") { model.beReceiver() }
            }
        }
        .padding(40)
    }
}

struct RoleCard: View {
    let title: String, subtitle: String, symbol: String, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 34, weight: .light))
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 200, height: 160)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.tint.opacity(hover ? 0.7 : 0.15), lineWidth: 1.5))
            .scaleEffect(hover ? 1.04 : 1)
            .shadow(color: Color.accentColor.opacity(hover ? 0.3 : 0), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
    }
}

// MARK: - host (show PIN)

struct HostView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 24) {
            RadiatingWaves()
            if case let .advertising(pin) = model.session.phase {
                Text("Enter this PIN on the other Mac").foregroundStyle(.secondary)
                Text(pin)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit().tracking(8)
                    .contentTransition(.numericText())
            } else {
                Spinner()
            }
            Button("Cancel") { model.reset() }.buttonStyle(.bordered)
        }
        .padding(40)
    }
}

// MARK: - receiver (bubbles)

struct ReceiverView: View {
    @EnvironmentObject var model: AppModel
    @State private var pinTarget: PeerBrowser.DiscoveredPeer?
    @State private var pin = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                if model.browser.peers.isEmpty { Spinner(size: 18) }
                Text(model.browser.peers.isEmpty
                     ? "Looking for nearby Macs…"
                     : "Tap a Mac to pair")
                    .font(.title3).foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            BubbleField(peers: model.browser.peers) { peer in
                pinTarget = peer; pin = ""
            }

            Button("Cancel") { model.reset() }.buttonStyle(.bordered).padding(.bottom, 16)
        }
        .sheet(item: $pinTarget) { peer in
            PINEntry(peerName: peer.id, pin: $pin) {
                model.session.join(peer.endpoint, pin: pin)
                pinTarget = nil
            } cancel: { pinTarget = nil }
        }
    }
}

/// Discovered Macs drift as glowing orbs; tap one to pair.
struct BubbleField: View {
    let peers: [PeerBrowser.DiscoveredPeer]
    let onTap: (PeerBrowser.DiscoveredPeer) -> Void

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    if peers.isEmpty {
                        RadiatingWaves()   // gentle "scanning" pulse, pure SwiftUI
                            .position(x: geo.size.width/2, y: geo.size.height/2)
                    }
                    ForEach(Array(peers.enumerated()), id: \.element.id) { i, peer in
                        Bubble(name: peer.id)
                            .position(orbit(i: i, count: peers.count, t: t, in: geo.size))
                            .onTapGesture { onTap(peer) }
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }

    /// gentle drift so bubbles feel alive without a physics engine
    func orbit(i: Int, count: Int, t: Double, in size: CGSize) -> CGPoint {
        let cx = size.width/2, cy = size.height/2
        let base = count <= 1 ? 0 : min(size.width, size.height) * 0.28
        let ang = (Double(i)/Double(max(count,1))) * 2 * .pi + t * 0.15
        let wobble = sin(t * 0.9 + Double(i)) * 10
        return CGPoint(x: cx + cos(ang) * (base + wobble),
                       y: cy + sin(ang) * (base + wobble))
    }
}

struct Bubble: View {
    let name: String
    @State private var appear = false
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.18))
                Circle().strokeBorder(.tint.opacity(0.5), lineWidth: 1.5)
                Image(systemName: "macbook").font(.system(size: 30, weight: .light))
            }
            .frame(width: 96, height: 96)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: Color.accentColor.opacity(0.35), radius: 18)
            Text(name).font(.callout.weight(.medium)).lineLimit(1)
        }
        .scaleEffect(appear ? 1 : 0.6).opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appear = true } }
    }
}

struct PINEntry: View {
    let peerName: String
    @Binding var pin: String
    let pair: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Pair with \(peerName)").font(.headline)
            Text("Enter the PIN shown on that Mac").font(.caption).foregroundStyle(.secondary)
            TextField("000000", text: $pin)
                .textFieldStyle(.roundedBorder).font(.system(.title, design: .rounded))
                .multilineTextAlignment(.center).frame(width: 160)
                .onSubmit(pair)
            HStack {
                Button("Cancel", action: cancel).buttonStyle(.bordered)
                Button("Pair", action: pair).buttonStyle(.borderedProminent)
                    .disabled(pin.count < 6)
            }
        }
        .padding(30).frame(width: 340)
    }
}
