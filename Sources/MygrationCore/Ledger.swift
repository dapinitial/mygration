import Foundation

/// A machine's self-description — the unit everything in Mygration operates on.
/// Capturing a Ledger never modifies the machine (read-only by design rule).
public struct Ledger: Codable, Equatable {
    public var machine: Machine
    public var brew: BrewState
    public var repos: [Repo]
    public var envFiles: [EnvFile]
    public var keychainRefs: [KeychainRef]
    public var node: NodeState
    public var vscodeExtensions: [String]
    public var agents: [DiscoveredAgent]
    public var services: [DiscoveredService]
    public var capturedAt: String
}

public struct Machine: Codable, Equatable {
    public var host: String
    /// "arm64" or "x86_64" — the input to the translation layer
    public var arch: String
    public var macOS: String
    /// "/opt/homebrew" (Apple Silicon) or "/usr/local" (Intel)
    public var brewPrefix: String?
    /// absolute $HOME — lets the target re-key path-encoded agent memory
    public var home: String = ""
}

public struct BrewState: Codable, Equatable {
    public var taps: [String]
    public var formulae: [Package]
    public var casks: [Package]

    public struct Package: Codable, Equatable {
        public var name: String
        public var version: String?
        public init(name: String, version: String? = nil) {
            self.name = name; self.version = version
        }
    }
}

public struct Repo: Codable, Equatable {
    public var name: String
    public var path: String
    public var remote: String?      // nil = marooned: cannot be restored by clone
    public var branch: String?
    public var dirty: Bool          // uncommitted changes → wip-snapshot lane
    public var unpushed: Bool       // local commits not on any remote
}

public struct EnvFile: Codable, Equatable {
    /// path relative to $HOME — gitignored by definition, travels encrypted
    public var path: String
    public var bytes: Int
}

public struct KeychainRef: Codable, Equatable {
    /// name + account ONLY — a Ledger never contains secret values
    public var service: String
    public var account: String
    public var sourceFile: String
}

public struct NodeState: Codable, Equatable {
    public var nodeVersion: String?
    public var nvmVersions: [String]
    public var npmGlobals: [String]
}

extension Ledger {
    /// Stable, diff-friendly JSON (sorted keys, pretty) — the wire format.
    public func json() throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(data: try enc.encode(self), encoding: .utf8)!
    }
}
