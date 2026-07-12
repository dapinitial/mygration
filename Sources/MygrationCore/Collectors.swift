import Foundation

/// Collectors read the machine into Ledger fields. Behavior is ported from the
/// field-proven bash kit (capture.sh / audit.sh), which remains the golden
/// reference — any divergence from it is a bug here unless a field note says
/// otherwise.
public enum Collect {

    public static func ledger(sitesDir: String) -> Ledger {
        Ledger(
            machine: machine(),
            brew: brew(),
            repos: repos(sitesDir: sitesDir),
            envFiles: envFiles(sitesDir: sitesDir),
            keychainRefs: keychainRefs(sitesDir: sitesDir),
            node: node(),
            vscodeExtensions: vscodeExtensions(),
            capturedAt: ISO8601DateFormatter().string(from: Date()))
    }

    // MARK: machine identity

    public static func machine() -> Machine {
        var u = utsname(); uname(&u)
        let arch = withUnsafeBytes(of: &u.machine) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        let prefix = sh("brew --prefix").lines.first
        return Machine(
            host: sh("scutil --get LocalHostName").lines.first ?? ProcessInfo.processInfo.hostName,
            arch: arch,
            macOS: sh("sw_vers -productVersion").lines.first ?? "unknown",
            brewPrefix: prefix)
    }

    // MARK: homebrew

    public static func brew() -> BrewState {
        func packages(_ cmd: String) -> [BrewState.Package] {
            sh(cmd).lines.map { line in
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                return BrewState.Package(name: parts[0], version: parts.count > 1 ? parts[1] : nil)
            }
        }
        return BrewState(
            taps: sh("brew tap").lines,
            formulae: packages("brew list --formula --versions"),
            casks: packages("brew list --cask --versions"))
    }

    // MARK: git repos (the code lane)

    public static func repos(sitesDir: String) -> [Repo] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: sitesDir) else { return [] }
        return entries.sorted().compactMap { name in
            let path = "\(sitesDir)/\(name)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: "\(path)/.git", isDirectory: &isDir), isDir.boolValue
            else { return nil }
            let remote = sh("git remote get-url origin", cwd: path)
            let branch = sh("git branch --show-current", cwd: path)
            return Repo(
                name: name,
                path: path,
                remote: remote.ok ? remote.lines.first : nil,
                branch: branch.lines.first,
                dirty: !sh("git status --porcelain", cwd: path).lines.isEmpty,
                unpushed: !sh("git log --branches --not --remotes --oneline", cwd: path).lines.isEmpty)
        }
    }

    // MARK: env files (gitignored by definition → encrypted lane)

    static let envNames: Set<String> = [".env", ".env.local", ".envrc"]
    static func isEnvName(_ n: String) -> Bool {
        envNames.contains(n) || (n.hasPrefix(".env.") && n.hasSuffix(".local"))
    }

    public static func envFiles(sitesDir: String) -> [EnvFile] {
        let home = NSHomeDirectory()
        return walk(sitesDir, maxDepth: 3).compactMap { path in
            guard isEnvName((path as NSString).lastPathComponent) else { return nil }
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let size = attrs?[.size] as? Int ?? 0
            var rel = path
            if rel.hasPrefix(home + "/") { rel.removeFirst(home.count + 1) }
            return EnvFile(path: rel, bytes: size)
        }.sorted { $0.path < $1.path }
    }

    // MARK: keychain references inside .envrc (names only, never values)

    public static func keychainRefs(sitesDir: String) -> [KeychainRef] {
        let home = NSHomeDirectory()
        let pattern = try! NSRegularExpression(
            pattern: #"security find-generic-password[^\n]*?-s +([^\s'"]+)[^\n]*?-a +([^\s'"]+)"#)
        var refs: [KeychainRef] = []
        for path in walk(sitesDir, maxDepth: 2) where (path as NSString).lastPathComponent == ".envrc" {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for m in pattern.matches(in: text, range: range) {
                guard let s = Range(m.range(at: 1), in: text),
                      let a = Range(m.range(at: 2), in: text) else { continue }
                var rel = path
                if rel.hasPrefix(home + "/") { rel.removeFirst(home.count + 1) }
                refs.append(KeychainRef(service: String(text[s]),
                                        account: String(text[a]),
                                        sourceFile: rel))
            }
        }
        return refs.sorted { $0.service < $1.service }
    }

    // MARK: node

    public static func node() -> NodeState {
        let nvmDir = NSHomeDirectory() + "/.nvm/versions/node"
        let nvm = (try? FileManager.default.contentsOfDirectory(atPath: nvmDir)) ?? []
        let globals = sh("npm ls -g --depth=0 --parseable 2>/dev/null").lines
            .dropFirst()
            .map { ($0 as NSString).lastPathComponent }
        return NodeState(
            nodeVersion: sh("node --version").lines.first,
            nvmVersions: nvm.sorted(),
            npmGlobals: globals.sorted())
    }

    // MARK: vscode

    public static func vscodeExtensions() -> [String] {
        sh("command -v code >/dev/null && code --list-extensions").lines.sorted()
    }

    // MARK: helpers

    /// Depth-limited file walk that never descends into node_modules or .git.
    static func walk(_ root: String, maxDepth: Int) -> [String] {
        var results: [String] = []
        func recurse(_ dir: String, depth: Int) {
            guard depth <= maxDepth,
                  let names = try? FileManager.default.contentsOfDirectory(atPath: dir)
            else { return }
            for n in names {
                if n == "node_modules" || n == ".git" { continue }
                let p = "\(dir)/\(n)"
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
                if isDir.boolValue { recurse(p, depth: depth + 1) } else { results.append(p) }
            }
        }
        recurse(root, depth: 1)
        return results
    }
}
