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

@MainActor
public final class PairingSession: ObservableObject {
    public enum Phase: Equatable {
        case idle, advertising(pin: String), connecting, established, paired(PeerInfo), failed(String)
    }
    @Published public private(set) var phase: Phase = .idle

    private var listener: NWListener?
    private var connection: NWConnection?

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
                    self.phase = .established
                    conn.send(content: frame(PeerInfo.mine()), completion: .contentProcessed { _ in })
                    self.receivePeer(conn)
                case .failed(let e): self.phase = .failed("\(e)")
                default: break
                }
            }
        }
        conn.start(queue: .main)
    }

    private nonisolated func receivePeer(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { d, _, _, _ in
            guard let d, d.count == 4 else { return }
            let n = Int(UInt32(bigEndian: d.withUnsafeBytes { $0.load(as: UInt32.self) }))
            conn.receive(minimumIncompleteLength: n, maximumLength: n) { body, _, _, _ in
                guard let body, let peer = try? JSONDecoder().decode(PeerInfo.self, from: body)
                else { return }
                Task { @MainActor [weak self] in self?.phase = .paired(peer) }
            }
        }
    }

    public func cancel() {
        connection?.cancel(); listener?.cancel()
        connection = nil; listener = nil; phase = .idle
    }
}
