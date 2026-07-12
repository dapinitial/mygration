import ArgumentParser
import Foundation
import MygrationCore

@main
struct Mygration: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "NameDrop for your whole Mac — it moves your setup, not your files.",
        version: "0.1.0",
        subcommands: [Capture.self])
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
