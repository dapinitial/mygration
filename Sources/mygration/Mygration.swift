import ArgumentParser
import Foundation
import MygrationCore

@main
struct Mygration: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "NameDrop for your whole Mac — it moves your setup, not your files.",
        version: "0.1.0",
        subcommands: [Capture.self, PairHost.self])
}

/// Debug: run the app's exact PairingSession.host() from the CLI so advertising
/// can be observed with dns-sd. Not user-facing.
struct PairHost: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pair-host", abstract: "Debug: advertise like the app does.")
    func run() throws {
        Task { @MainActor in
            let session = PairingSession()
            session.host()
            NSLog("[Mygration] CLI pair-host started; ^C to stop")
            _ = session   // retain
        }
        RunLoop.main.run()
    }
}

struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read this machine into a Ledger (JSON). Never modifies anything.")

    @Option(name: .long, help: "Projects directory to scan.")
    var sites: String = NSHomeDirectory() + "/Sites"

    @Option(name: .long, help: "Write the ledger to a file instead of stdout.")
    var output: String?

    func run() throws {
        let ledger = Collect.ledger(sitesDir: (sites as NSString).expandingTildeInPath)
        let json = try ledger.json()
        if let output {
            try json.write(toFile: (output as NSString).expandingTildeInPath,
                           atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("ledger → \(output)\n".utf8))
        } else {
            print(json)
        }
    }
}
