import SwiftUI
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

    enum Mode { case choosing, hosting, joining }

    func beHost() { mode = .hosting; session.host() }
    func beReceiver() { mode = .joining; browser.start() }
    func reset() {
        session.cancel(); browser.stop(); mode = .choosing
    }
}
