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
