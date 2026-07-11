// pair — Mygration pairing-ceremony spike.
//
//   pair host    on one Mac: advertises via Bonjour/AWDL, displays a PIN
//   pair join    on another: discovers the host, asks for the PIN
//
// The PIN derives a TLS pre-shared key, so the encrypted channel can only be
// established by someone who read the PIN off the host's screen. Wrong PIN =
// TLS handshake failure = no channel. This is the app's trust model, minimal.

import Foundation
import Network
import CryptoKit

let SERVICE_TYPE = "_mygration._tcp"

setvbuf(stdout, nil, _IONBF, 0)   // unbuffered: PINs must appear immediately, even piped

// MARK: - identity

func deviceName() -> String { Host.current().localizedName ?? "unknown-mac" }

func deviceArch() -> String {
    var u = utsname(); uname(&u)
    return withUnsafeBytes(of: &u.machine) { raw in
        String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
    }
}

struct Hello: Codable {
    let name: String, arch: String, os: String
    static func mine() -> Hello {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return Hello(name: deviceName(), arch: deviceArch(),
                     os: "\(v.majorVersion).\(v.minorVersion)")
    }
}

// MARK: - PIN → TLS pre-shared key

func makePIN() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }

func tlsOptions(pin: String) -> NWProtocolTLS.Options {
    let opts = NWProtocolTLS.Options()
    let keyData = SHA256.hash(data: Data("mygration-pair-v1:\(pin)".utf8))
        .withUnsafeBytes { DispatchData(bytes: $0) }
    let hint = Data("mygration".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
    sec_protocol_options_add_pre_shared_key(
        opts.securityProtocolOptions, keyData as __DispatchData, hint as __DispatchData)
    sec_protocol_options_append_tls_ciphersuite(
        opts.securityProtocolOptions,
        tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
    sec_protocol_options_set_min_tls_protocol_version(opts.securityProtocolOptions, .TLSv12)
    sec_protocol_options_set_max_tls_protocol_version(opts.securityProtocolOptions, .TLSv12)
    return opts
}

func parameters(pin: String) -> NWParameters {
    let params = NWParameters(tls: tlsOptions(pin: pin))
    params.includePeerToPeer = true   // AWDL: works with no shared network
    return params
}

// MARK: - framing (4-byte big-endian length prefix + JSON)

func send<T: Codable>(_ msg: T, over conn: NWConnection) {
    let body = try! JSONEncoder().encode(msg)
    var len = UInt32(body.count).bigEndian
    var frame = Data(bytes: &len, count: 4); frame.append(body)
    conn.send(content: frame, completion: .contentProcessed { _ in })
}

func receiveHello(over conn: NWConnection, _ done: @escaping (Hello) -> Void) {
    conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, _ in
        guard let data, data.count == 4 else { return }
        let len = Int(UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) }))
        conn.receive(minimumIncompleteLength: len, maximumLength: len) { body, _, _, _ in
            guard let body, let hello = try? JSONDecoder().decode(Hello.self, from: body)
            else { return }
            done(hello)
        }
    }
}

func ceremony(on conn: NWConnection, role: String) {
    var ready = false
    if role == "join" {
        // a wrong PSK never surfaces as .failed — the host just drops the
        // handshake and the client sits in .preparing. Deadline = rejection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if !ready {
                print("✗ pairing rejected — wrong PIN (handshake never completed)")
                conn.cancel(); exit(1)
            }
        }
    }
    conn.stateUpdateHandler = { state in
        switch state {
        case .ready:
            ready = true
            print("🔐 encrypted channel established")
            send(Hello.mine(), over: conn)
            receiveHello(over: conn) { peer in
                print("""

                ✅ PAIRED with \(peer.name)
                   arch: \(peer.arch) (you: \(deviceArch()))  macOS \(peer.os)
                   ledger exchange would begin here.
                """)
                exit(0)
            }
        case .failed(let err):
            print(role == "join"
                  ? "✗ pairing failed — wrong PIN, or host gone (\(err))"
                  : "✗ connection failed (\(err))")
            exit(1)
        case .waiting(let err):
            // a wrong PSK never hard-fails — TLS parks in .waiting and retries.
            // For the ceremony, waiting IS rejection.
            print("✗ pairing rejected — check the PIN and try again (\(err))")
            conn.cancel()
            exit(1)
        default: break
        }
    }
    conn.start(queue: .main)
}

// MARK: - host

func runHost() {
    let pin = makePIN()
    let listener = try! NWListener(using: parameters(pin: pin))
    listener.service = NWListener.Service(name: deviceName(), type: SERVICE_TYPE)
    listener.newConnectionHandler = { conn in
        print("→ \(String(describing: conn.endpoint)) is attempting to pair…")
        ceremony(on: conn, role: "host")
    }
    listener.stateUpdateHandler = { state in
        if case .ready = state {
            print("""

            ╭──────────────────────────────────╮
            │   Mygration pairing — HOST       │
            │                                  │
            │   PIN:  \(pin)                 │
            │                                  │
            │   run `pair join` on the other   │
            │   Mac and enter this PIN         │
            ╰──────────────────────────────────╯
            advertising as “\(deviceName())” (\(SERVICE_TYPE), P2P on)…
            """)
        }
        if case .failed(let err) = state { print("✗ listener failed: \(err)"); exit(1) }
    }
    listener.start(queue: .main)
    dispatchMain()
}

// MARK: - join

func runJoin() {
    print("searching for nearby Macs…")
    let browser = NWBrowser(for: .bonjour(type: SERVICE_TYPE, domain: nil),
                            using: { let p = NWParameters(); p.includePeerToPeer = true; return p }())
    var connecting = false
    browser.browseResultsChangedHandler = { results, _ in
        guard !connecting, let first = results.first else { return }
        connecting = true
        if case let .service(name, _, _, _) = first.endpoint {
            print("found “\(name)”")
        }
        print("enter the PIN shown on that Mac: ", terminator: "")
        guard let pin = readLine(), !pin.isEmpty else { print("no PIN entered"); exit(1) }
        browser.cancel()
        ceremony(on: NWConnection(to: first.endpoint, using: parameters(pin: pin)),
                 role: "join")
    }
    browser.start(queue: .main)
    dispatchMain()
}

// MARK: - entry

switch CommandLine.arguments.dropFirst().first {
case "host": runHost()
case "join": runJoin()
default:
    print("usage: pair host   (shows PIN)\n       pair join   (finds host, asks PIN)")
    exit(64)
}
