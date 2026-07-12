import Foundation
import Network
import CryptoKit
import Combine

/// Shared pairing engine (extracted from spike/pairing, now the real thing).
/// The PIN derives a TLS pre-shared key: a wrong PIN can't establish the
/// channel at all. UI-friendly — everything published on the main actor.

public let MYG_SERVICE_TYPE = "_mygration._tcp"

public struct PeerInfo: Codable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let arch: String
    public let os: String
    public static func mine() -> PeerInfo {
        var u = utsname(); uname(&u)
        let arch = withUnsafeBytes(of: &u.machine) {
            String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return PeerInfo(name: Host.current().localizedName ?? "Mac",
                        arch: arch, os: "\(v.majorVersion).\(v.minorVersion)")
    }
}

// MARK: - PIN → TLS-PSK parameters

public func mygPIN() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }

func tlsPSK(pin: String) -> NWParameters {
    let tls = NWProtocolTLS.Options()
    let key = SHA256.hash(data: Data("mygration-pair-v1:\(pin)".utf8))
        .withUnsafeBytes { DispatchData(bytes: $0) }
    let hint = Data("mygration".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
    sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,
                                            key as __DispatchData, hint as __DispatchData)
    sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
        tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
    sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
    sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
    let p = NWParameters(tls: tls)
    p.includePeerToPeer = true
    return p
}

func frame<T: Encodable>(_ m: T) -> Data {
    let body = try! JSONEncoder().encode(m)
    var len = UInt32(body.count).bigEndian
    var d = Data(bytes: &len, count: 4); d.append(body); return d
}

// MARK: - discovery (browser)

@MainActor
public final class PeerBrowser: ObservableObject {
    @Published public private(set) var peers: [DiscoveredPeer] = []
    private var browser: NWBrowser?

    public struct DiscoveredPeer: Identifiable, Equatable {
        public let id: String            // service name
        public let endpoint: NWEndpoint
        public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    }

    public init() {}

    public func start() {
        let params = NWParameters(); params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: MYG_SERVICE_TYPE, domain: nil), using: params)
        b.stateUpdateHandler = { state in NSLog("[Mygration] browser state: \(state)") }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            NSLog("[Mygration] browser results: \(results.count) — \(results.map { "\($0.endpoint)" })")
            Task { @MainActor in
                self?.peers = results.compactMap { r in
                    if case let .service(name, _, _, _) = r.endpoint {
                        return DiscoveredPeer(id: name, endpoint: r.endpoint)
                    }
                    return nil
                }
            }
        }
        b.start(queue: .main)
        browser = b
        NSLog("[Mygration] browsing for \(MYG_SERVICE_TYPE)")
    }

    public func stop() { browser?.cancel(); browser = nil; peers = [] }
}

// MARK: - pairing session (host or join)

/// One framed message on the pairing wire.
struct Wire: Codable {
    let kind: String            // "hello" | "ledger" | "fileRequest" | "treeRequest" | "fileData"
    var hello: PeerInfo? = nil
    var ledger: Ledger? = nil
    var paths: [String]? = nil  // file/treeRequest: HOME-relative paths the peer wants
    var path: String? = nil     // fileData: one path
    var dataB64: String? = nil  // fileData: its contents
}

/// Files under a directory that should never be streamed: session transcripts,
/// caches, and anything huge. Keeps agent-memory transfer to the curated brain.
func mygExcluded(_ rel: String) -> Bool {
    if rel.hasSuffix(".jsonl") { return true }               // session transcripts
    let junk = ["/cache/", "/sessions/", "/shell-snapshots/", "/paste-cache/",
                "/file-history/", "/downloads/", "/statsig/", "/todos/", "/.DS_Store"]
    return junk.contains { rel.contains($0) }
}

/// HOME-relative files under a root (file or directory), minus excluded junk.
func mygEnumerate(homeRel root: String, home: String) -> [String] {
    let full = "\(home)/\(root)"
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir) else { return [] }
    if !isDir.boolValue { return mygExcluded(root) ? [] : [root] }
    var out: [String] = []
    if let en = FileManager.default.enumerator(atPath: full) {
        while let f = en.nextObject() as? String {
            let rel = "\(root)/\(f)"
            var d: ObjCBool = false
            FileManager.default.fileExists(atPath: "\(home)/\(rel)", isDirectory: &d)
            if d.boolValue || mygExcluded(rel) { continue }
            out.append(rel)
            if out.count > 8000 { break }
        }
    }
    return out
}

@MainActor
public final class PairingSession: ObservableObject {
    public enum Phase: Equatable {
        case idle, advertising(pin: String), connecting, established, paired(PeerInfo), failed(String)
    }
    @Published public private(set) var phase: Phase = .idle
    /// The OTHER machine's ledger — what could migrate FROM it TO here.
    @Published public private(set) var peerLedger: Ledger?
    /// Files received from the peer over the secure channel (HOME-relative path → bytes).
    @Published public private(set) var receivedFiles: [String: Data] = [:]

    private var listener: NWListener?
    private var connection: NWConnection?
    /// Roots to scan when sending our ledger (set by the app before hosting/joining).
    public var codeRoots: [String] = []
    /// Security boundary: we only serve files we ourselves advertised in our ledger.
    private var servablePaths: Set<String> = []

    /// Ask the peer to send these HOME-relative files over the encrypted channel.
    public func requestFiles(_ paths: [String]) {
        guard let conn = connection, !paths.isEmpty else { return }
        conn.send(content: frame(Wire(kind: "fileRequest", paths: paths)), completion: .contentProcessed { _ in })
    }

    /// Ask the peer to stream everything under these HOME-relative directory roots
    /// (agent memory), minus excluded caches/transcripts.
    public func requestTree(_ roots: [String]) {
        guard let conn = connection, !roots.isEmpty else { return }
        conn.send(content: frame(Wire(kind: "treeRequest", paths: roots)), completion: .contentProcessed { _ in })
    }

    public init() {}

    /// Host: advertise and show a PIN. Returns the PIN via the published phase.
    public func host() {
        let pin = mygPIN()
        do {
            let l = try NWListener(using: tlsPSK(pin: pin))
            l.service = .init(name: PeerInfo.mine().name, type: MYG_SERVICE_TYPE)
            l.serviceRegistrationUpdateHandler = { change in
                NSLog("[Mygration] listener service registration: \(change)")
            }
            l.stateUpdateHandler = { [weak self] state in
                NSLog("[Mygration] listener state: \(state)")
                Task { @MainActor in
                    if case .failed(let e) = state { self?.phase = .failed("advertise failed: \(e)") }
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                NSLog("[Mygration] incoming connection")
                Task { @MainActor in self?.attach(conn, role: .host) }
            }
            l.start(queue: .main)
            listener = l
            phase = .advertising(pin: pin)
            NSLog("[Mygration] hosting, PIN \(pin), advertising \(MYG_SERVICE_TYPE) as \(PeerInfo.mine().name)")
        } catch { phase = .failed("\(error)") }
    }

    /// Join: connect to a discovered endpoint using the typed PIN.
    public func join(_ endpoint: NWEndpoint, pin: String) {
        phase = .connecting
        attach(NWConnection(to: endpoint, using: tlsPSK(pin: pin)), role: .join)
    }

    private enum Role { case host, join }

    private func attach(_ conn: NWConnection, role: Role) {
        connection = conn
        // wrong PSK never hard-fails; the handshake just never readies → deadline = rejection
        if role == .join {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if case .connecting = self?.phase {
                    self?.phase = .failed("wrong PIN — the secure channel never opened")
                    conn.cancel()
                }
            }
        }
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    NSLog("[Mygration] connection READY (\(role)) — secure channel up")
                    self.phase = .established
                    // 1) hello immediately, 2) our full ledger (captured off-thread)
                    conn.send(content: frame(Wire(kind: "hello", hello: .mine())),
                              completion: .contentProcessed { _ in })
                    let roots = self.codeRoots.isEmpty ? Collect.discoverCodeRoots() : self.codeRoots
                    Task.detached { [weak self] in
                        let led = Collect.ledger(codeRoots: roots)
                        let serve = Set(led.envFiles.map(\.path)).union(led.agents.flatMap(\.transferPaths))
                        await MainActor.run { self?.servablePaths = serve }
                        conn.send(content: frame(Wire(kind: "ledger", ledger: led)),
                                  completion: .contentProcessed { _ in })
                        NSLog("[Mygration] sent our ledger (\(led.repos.count) repos, \(led.agents.count) agents)")
                    }
                    self.receiveLoop(conn)
                case .failed(let e):
                    NSLog("[Mygration] connection FAILED (\(role)): \(e)")
                    self.phase = .failed("\(e)")
                case .waiting(let e):
                    NSLog("[Mygration] connection WAITING (\(role)): \(e)")
                case .cancelled:
                    NSLog("[Mygration] connection cancelled (\(role))")
                default: break
                }
            }
        }
        conn.start(queue: .main)
    }

    /// Continuously read length-prefixed Wire frames (hello, then ledger, …).
    private nonisolated func receiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] d, _, _, _ in
            guard let self, let d, d.count == 4 else { return }
            let n = Int(UInt32(bigEndian: d.withUnsafeBytes { $0.load(as: UInt32.self) }))
            conn.receive(minimumIncompleteLength: n, maximumLength: n) { body, _, _, _ in
                if let body, let msg = try? JSONDecoder().decode(Wire.self, from: body) {
                    switch msg.kind {
                    case "hello":
                        if let peer = msg.hello {
                            NSLog("[Mygration] PAIRED with \(peer.name) (\(peer.arch))")
                            Task { @MainActor in self.phase = .paired(peer) }
                        }
                    case "ledger":
                        if let led = msg.ledger {
                            NSLog("[Mygration] received peer ledger: \(led.repos.count) repos, \(led.agents.count) agents, \(led.brew.formulae.count) formulae")
                            Task { @MainActor in self.peerLedger = led }
                        }
                    case "fileRequest":
                        // serve ONLY files we advertised in our own ledger
                        let home = NSHomeDirectory()
                        Task { @MainActor in
                            for p in (msg.paths ?? []) where self.servablePaths.contains(p) {
                                if let data = FileManager.default.contents(atPath: "\(home)/\(p)") {
                                    conn.send(content: frame(Wire(kind: "fileData", path: p,
                                                                  dataB64: data.base64EncodedString())),
                                              completion: .contentProcessed { _ in })
                                }
                            }
                            NSLog("[Mygration] served \((msg.paths ?? []).filter { self.servablePaths.contains($0) }.count) files")
                        }
                    case "treeRequest":
                        let home = NSHomeDirectory()
                        Task { @MainActor in
                            var sent = 0
                            for root in (msg.paths ?? []) where self.servablePaths.contains(root) {
                                for rel in mygEnumerate(homeRel: root, home: home) {
                                    guard let data = FileManager.default.contents(atPath: "\(home)/\(rel)"),
                                          data.count < 8_000_000 else { continue }
                                    conn.send(content: frame(Wire(kind: "fileData", path: rel,
                                                                  dataB64: data.base64EncodedString())),
                                              completion: .contentProcessed { _ in })
                                    sent += 1
                                }
                            }
                            NSLog("[Mygration] served tree: \(sent) files")
                        }
                    case "fileData":
                        if let p = msg.path, let b64 = msg.dataB64, let data = Data(base64Encoded: b64) {
                            Task { @MainActor in self.receivedFiles[p] = data }
                        }
                    default: break
                    }
                }
                self.receiveLoop(conn)   // keep reading
            }
        }
    }

    public func cancel() {
        connection?.cancel(); listener?.cancel()
        connection = nil; listener = nil; phase = .idle
    }
}
