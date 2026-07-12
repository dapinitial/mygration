import SwiftUI
import Combine
import MygrationCore

@main
struct MygrationApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        // Menu bar presence — the daily-driver surface
        MenuBarExtra("Mygration", systemImage: "arrow.triangle.2.circlepath") {
            MenuBarView().environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        // The migration window — the NameDrop moment
        Window("Mygration", id: "main") {
            DiscoveryView().environmentObject(model)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // The 3D ledger constellation
        Window("Ledger", id: "graph") {
            LedgerWindow().environmentObject(model)
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)

        // The à-la-carte migration plan
        Window("Migration Plan", id: "plan") {
            PlanWindow().environmentObject(model)
                .frame(minWidth: 620, minHeight: 560)
        }
    }
}

/// Shows the selectable plan. Prefers the PEER's ledger (what would migrate FROM
/// the other Mac) once paired; otherwise previews THIS Mac's ledger.
struct PlanWindow: View {
    @EnvironmentObject var model: AppModel
    @State private var localLedger: Ledger?
    private var loading: String {
        model.session.peerLedger == nil && localLedger == nil ? "Reading this Mac…" : ""
    }
    var body: some View {
        Group {
            if let peer = model.session.peerLedger {
                PlanView(ledger: peer, session: model.session)   // real: source Mac's contents, over the channel
            } else if let localLedger {
                PlanView(ledger: localLedger)   // preview of this Mac when unpaired
            } else {
                VStack(spacing: 14) { Spinner(size: 30); Text("Reading this Mac…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .task {
            if model.session.peerLedger == nil {
                let roots = Collect.discoverCodeRoots()
                localLedger = await Task.detached { Collect.ledger(codeRoots: roots) }.value
            }
        }
    }
}

/// Captures this Mac's ledger (off the main thread) then renders the graph.
struct LedgerWindow: View {
    @State private var ledger: Ledger?
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.043, blue: 0.078).ignoresSafeArea()
            if let ledger {
                LedgerGraphView(ledger: ledger)
            } else {
                VStack(spacing: 14) {
                    Spinner(size: 34)
                    Text("Reading this Mac…").foregroundStyle(.secondary)
                }
            }
        }
        .task {
            let roots = Collect.discoverCodeRoots()
            let l = await Task.detached { Collect.ledger(codeRoots: roots) }.value
            withAnimation(.easeOut(duration: 0.4)) { ledger = l }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let browser = PeerBrowser()
    let session = PairingSession()
    @Published var mode: Mode = .choosing
    private var bag = Set<AnyCancellable>()

    enum Mode { case choosing, hosting, joining }

    init() {
        // nested ObservableObjects don't auto-propagate — forward their changes
        // so views observing AppModel redraw when peers/phase update.
        browser.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    }

    func beHost() { mode = .hosting; session.host() }
    func beReceiver() { mode = .joining; browser.start() }
    func flashScreen() { ScreenRippleController.shared.flash() }
    func reset() {
        session.cancel(); browser.stop(); mode = .choosing
    }
}
