import Foundation

/// Executes a selected migration plan on THIS machine, using the source Mac's
/// ledger. Real actions: clone selected repos from their remotes, install
/// selected Homebrew packages natively. Secret-bearing categories (env files,
/// keychain, agent state) are reported as pending secure transfer — honest
/// about what does and doesn't move yet.
@MainActor
public final class Executor: ObservableObject {
    public struct Line: Identifiable, Equatable {
        public let id = UUID()
        public var text: String
        public var status: Status
        public enum Status: String { case running, ok, fail, info, skip }
    }

    @Published public private(set) var lines: [Line] = []
    @Published public private(set) var done = false
    @Published public private(set) var running = false

    /// Set to enable secure file transfer (env files) over the pairing channel.
    public var session: PairingSession?

    public init() {}

    public func start(source: Ledger, selected: Set<String>, targetRoot: String) {
        guard !running else { return }
        running = true; done = false; lines = []
        Task { await execute(source: source, selected: selected, targetRoot: targetRoot) }
    }

    private func add(_ text: String, _ status: Line.Status) -> UUID {
        let l = Line(text: text, status: status); lines.append(l); return l.id
    }
    private func set(_ id: UUID, _ text: String, _ status: Line.Status) {
        if let i = lines.firstIndex(where: { $0.id == id }) { lines[i].text = text; lines[i].status = status }
    }

    private func execute(source: Ledger, selected: Set<String>, targetRoot: String) async {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: targetRoot, withIntermediateDirectories: true)

        // 1) repos → git clone from their remotes
        let repos = source.repos.filter { selected.contains("repos:\($0.name)") }
        for r in repos {
            guard let remote = r.remote else {
                _ = add("\(r.name) — skipped (no remote)", .skip); continue
            }
            let dest = "\(targetRoot)/\(r.name)"
            if fm.fileExists(atPath: dest) { _ = add("\(r.name) — already present", .info); continue }
            let id = add("Cloning \(r.name)…", .running)
            let res = await bg { sh("git clone \(remote) '\(dest)'") }
            set(id, res.ok ? "Cloned \(r.name)" : "Failed \(r.name): \(res.stderr.split(separator: "\n").last.map(String.init) ?? "")",
                res.ok ? .ok : .fail)
        }

        // 2) Homebrew → one brew bundle for all selected packages
        let formulae = source.brew.formulae.filter { selected.contains("brew:f-\($0.name)") }.map(\.name)
        let casks = source.brew.casks.filter { selected.contains("brew:c-\($0.name)") }.map(\.name)
        if !formulae.isEmpty || !casks.isEmpty {
            let id = add("Installing \(formulae.count) formulae + \(casks.count) casks…", .running)
            let body = (formulae.map { "brew \"\($0)\"" } + casks.map { "cask \"\($0)\"" }).joined(separator: "\n")
            let tmp = NSTemporaryDirectory() + "Brewfile.mygration"
            try? body.write(toFile: tmp, atomically: true, encoding: .utf8)
            let res = await bg { sh("brew bundle --file='\(tmp)' --no-upgrade 2>&1") }
            let installed = res.stdout.components(separatedBy: "Installing ").count - 1
            set(id, res.ok ? "Homebrew ready (\(installed) newly installed)" : "brew bundle had issues — see Console",
                res.ok ? .ok : .fail)
        }

        // 3) env files → streamed over the encrypted pairing channel, written into place
        let envPaths = source.envFiles.filter { selected.contains("env:\($0.path)") }.map(\.path)
        if !envPaths.isEmpty, let session {
            let id = add("Requesting \(envPaths.count) env files over secure channel…", .running)
            session.requestFiles(envPaths)
            for _ in 0..<60 {   // wait up to ~6s for arrival
                try? await Task.sleep(nanoseconds: 100_000_000)
                if envPaths.allSatisfy({ session.receivedFiles[$0] != nil }) { break }
            }
            var wrote = 0
            for p in envPaths {
                guard let data = session.receivedFiles[p] else { continue }
                let dest = "\(NSHomeDirectory())/\(p)"
                try? fm.createDirectory(atPath: (dest as NSString).deletingLastPathComponent,
                                        withIntermediateDirectories: true)
                if (try? data.write(to: URL(fileURLWithPath: dest))) != nil { wrote += 1 }
            }
            set(id, "Transferred \(wrote)/\(envPaths.count) env files (encrypted)",
                wrote == envPaths.count ? .ok : .fail)
        } else if !envPaths.isEmpty {
            _ = add("\(envPaths.count) env files — pair the Macs to transfer securely", .info)
        }
        let keyN = source.keychainRefs.filter { selected.contains("keychain:\($0.service)") }.count
        if keyN > 0 { _ = add("\(keyN) keychain tokens — re-enter on this Mac (never copied)", .info) }

        // 4) AI agent memory → stream curated tree over the encrypted channel, re-keyed
        let agents = source.agents.filter { selected.contains("agents:\($0.id)") }
        for a in agents {
            if a.regenerateOnly { _ = add("\(a.name) — re-pull models on this Mac (not copied)", .info); continue }
            guard let session, !a.transferPaths.isEmpty else {
                _ = add("\(a.name) — pair the Macs to transfer memory", .info); continue }
            let id = add("Transferring \(a.name) memory…", .running)
            session.requestTree(a.transferPaths)
            var last = -1
            for _ in 0..<80 {   // wait for the tree to arrive and settle (~8s max)
                try? await Task.sleep(nanoseconds: 100_000_000)
                let c = session.receivedFiles.keys.filter { key in a.transferPaths.contains { key.hasPrefix($0) } }.count
                if c > 0 && c == last { break }; last = c
            }
            var wrote = 0
            for (p, data) in session.receivedFiles where a.transferPaths.contains(where: { p.hasPrefix($0) }) {
                let rekeyed = mygRekey(p, sourceHome: source.machine.home, targetHome: NSHomeDirectory())
                let dest = "\(NSHomeDirectory())/\(rekeyed)"
                try? fm.createDirectory(atPath: (dest as NSString).deletingLastPathComponent,
                                        withIntermediateDirectories: true)
                if (try? data.write(to: URL(fileURLWithPath: dest))) != nil { wrote += 1 }
            }
            set(id, "\(a.name): \(wrote) memory files transferred" + (a.reauth != nil ? " · sign in to finish" : ""),
                wrote > 0 ? .ok : .fail)
        }

        // 5) beyond-brew: auto-install the cask-backed ones; surface the rest
        for x in source.beyondBrew where selected.contains("extras:\(x.id)") {
            if x.reinstall.hasPrefix("brew install") {
                let id = add("Installing \(x.name)…", .running)
                let res = await bg { sh("\(x.reinstall) 2>&1") }
                set(id, res.ok ? "Installed \(x.name)" : "\(x.name): \(x.reinstall) (finish manually)",
                    res.ok ? .ok : .info)
            } else {
                _ = add("\(x.name): \(x.reinstall)", .info)   // App Store / vendor — manual
            }
        }

        _ = add("Done.", .ok)
        running = false; done = true
    }

    /// Run a blocking shell call off the main actor.
    private func bg<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }
}
