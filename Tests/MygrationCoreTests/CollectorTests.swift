import XCTest
@testable import MygrationCore

/// Fixture-based tests: build a fake ~/Sites in a temp dir with real git repos
/// and .envrc files, then assert the collectors read exactly what bash did.
final class CollectorTests: XCTestCase {
    var sites: String!

    override func setUpWithError() throws {
        sites = NSTemporaryDirectory() + "mygration-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: sites, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: sites)
    }

    private func makeRepo(_ name: String, remote: String? = nil,
                          dirty: Bool = false, unpushed: Bool = false) throws {
        let p = "\(sites!)/\(name)"
        try FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        sh("git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init", cwd: p)
        if let remote {
            // mark current HEAD as pushed; without this, ANY commit counts as
            // unpushed (the collector is right about that — bash agrees)
            sh("git remote add origin '\(remote)' && git update-ref refs/remotes/origin/main HEAD", cwd: p)
        }
        if unpushed {
            sh("git -c user.email=t@t -c user.name=t commit -q --allow-empty -m ahead", cwd: p)
        }
        if dirty { FileManager.default.createFile(atPath: "\(p)/x.txt", contents: Data("x".utf8)) }
    }

    func testReposCollector() throws {
        try makeRepo("clean", remote: "git@github.com:me/clean.git")
        try makeRepo("marooned")                                   // no remote
        try makeRepo("messy", remote: "git@github.com:me/messy.git", dirty: true, unpushed: true)
        FileManager.default.createFile(atPath: "\(sites!)/not-a-repo-file", contents: nil)

        let repos = Collect.repos(sitesDir: sites)
        XCTAssertEqual(repos.map(\.name), ["clean", "marooned", "messy"])  // sorted, non-repos skipped

        let clean = repos[0], marooned = repos[1], messy = repos[2]
        XCTAssertEqual(clean.remote, "git@github.com:me/clean.git")
        XCTAssertEqual(clean.branch, "main")
        XCTAssertFalse(clean.dirty); XCTAssertFalse(clean.unpushed)
        XCTAssertNil(marooned.remote)
        XCTAssertTrue(messy.dirty); XCTAssertTrue(messy.unpushed)
    }

    func testEnvFilesCollector() throws {
        try FileManager.default.createDirectory(atPath: "\(sites!)/app/sub/node_modules/pkg",
                                                withIntermediateDirectories: true)
        for f in ["app/.env", "app/.envrc", "app/sub/.env.production.local",
                  "app/sub/node_modules/pkg/.env",   // must be skipped
                  "app/README.md"] {                  // not an env file
            FileManager.default.createFile(atPath: "\(sites!)/\(f)", contents: Data("K=1".utf8))
        }
        let found = Collect.envFiles(sitesDir: sites).map(\.path)
        XCTAssertEqual(found.count, 3)
        XCTAssertTrue(found.allSatisfy { !$0.contains("node_modules") && !$0.contains("README") })
    }

    func testKeychainRefsNeverContainValues() throws {
        try FileManager.default.createDirectory(atPath: "\(sites!)/proj", withIntermediateDirectories: true)
        let envrc = """
        # token lives in the keychain
        export API_TOKEN="$(security find-generic-password -s proj-service -a alice -w 2>/dev/null)"
        """
        FileManager.default.createFile(atPath: "\(sites!)/proj/.envrc", contents: Data(envrc.utf8))

        let refs = Collect.keychainRefs(sitesDir: sites)
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs[0].service, "proj-service")
        XCTAssertEqual(refs[0].account, "alice")
        // the Ledger invariant: names only, never secret values
        let json = try Ledger(machine: Collect.machine(), brew: BrewState(taps: [], formulae: [], casks: []),
                              repos: [], envFiles: [], keychainRefs: refs,
                              node: NodeState(nodeVersion: nil, nvmVersions: [], npmGlobals: []),
                              vscodeExtensions: [], capturedAt: "t").json()
        XCTAssertFalse(json.contains("-w"))
    }

    func testLedgerJSONIsStable() throws {
        let l = Ledger(machine: Machine(host: "h", arch: "arm64", macOS: "26.5", brewPrefix: "/opt/homebrew"),
                       brew: BrewState(taps: [], formulae: [BrewState.Package(name: "git", version: "2.4")], casks: []),
                       repos: [], envFiles: [], keychainRefs: [],
                       node: NodeState(nodeVersion: "v22", nvmVersions: [], npmGlobals: []),
                       vscodeExtensions: [], capturedAt: "2026-07-12T00:00:00Z")
        XCTAssertEqual(try l.json(), try l.json())              // deterministic
        XCTAssertTrue(try l.json().contains("\"arch\" : \"arm64\""))
    }
}
