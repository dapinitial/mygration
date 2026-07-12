import XCTest
@testable import MygrationCore

/// Tests for the security-critical transfer logic: what gets excluded from an
/// agent-memory stream, tree enumeration, and path re-keying across machines.
final class TransferTests: XCTestCase {

    func testExclusionDropsTranscriptsAndCaches() {
        // session transcripts and caches must never travel
        XCTAssertTrue(mygExcluded(".claude/projects/x/session.jsonl"))
        XCTAssertTrue(mygExcluded(".claude/cache/blob"))
        XCTAssertTrue(mygExcluded(".claude/shell-snapshots/s"))
        XCTAssertTrue(mygExcluded(".claude/paste-cache/p"))
        // curated memory + skills must survive
        XCTAssertFalse(mygExcluded(".claude/projects/x/memory/note.md"))
        XCTAssertFalse(mygExcluded(".claude/skills/foo/SKILL.md"))
        XCTAssertFalse(mygExcluded(".claude/CLAUDE.md"))
    }

    func testEnumerateKeepsMemoryDropsTranscripts() throws {
        let home = NSTemporaryDirectory() + "myg-tree-\(UUID().uuidString)"
        let fm = FileManager.default
        let mem = "\(home)/.claude/projects/proj/memory"
        try fm.createDirectory(atPath: mem, withIntermediateDirectories: true)
        fm.createFile(atPath: "\(mem)/fact.md", contents: Data("hi".utf8))
        fm.createFile(atPath: "\(home)/.claude/projects/proj/session-abc.jsonl", contents: Data("[]".utf8))
        defer { try? fm.removeItem(atPath: home) }

        let files = mygEnumerate(homeRel: ".claude/projects", home: home)
        XCTAssertTrue(files.contains(".claude/projects/proj/memory/fact.md"))
        XCTAssertFalse(files.contains { $0.hasSuffix(".jsonl") })   // transcript excluded
    }

    func testRekeySameHomeIsIdentity() {
        let p = ".claude/projects/-Users-dpuerto-Sites-migration/memory/x.md"
        XCTAssertEqual(mygRekey(p, sourceHome: "/Users/dpuerto", targetHome: "/Users/dpuerto"), p)
    }

    func testRekeyDifferentUsernameRemapsProjectDir() {
        let p = ".claude/projects/-Users-alice-Sites-app/memory/x.md"
        let out = mygRekey(p, sourceHome: "/Users/alice", targetHome: "/Users/bob")
        XCTAssertEqual(out, ".claude/projects/-Users-bob-Sites-app/memory/x.md")
    }

    func testKnownCaskHintsAreValidCommands() {
        // every catalogued cask maps to a real `brew install --cask` slug (no spaces)
        for (_, slug) in ExtrasCatalog.knownCasks {
            XCTAssertFalse(slug.contains(" "), "cask slug '\(slug)' must not contain spaces")
            XCTAssertFalse(slug.isEmpty)
        }
    }

    func testAgentCatalogSecretsNeverInTransferPaths() {
        // a tool's secret paths must never be in its curated transfer set
        for tool in AgentCatalog.all {
            for secret in tool.secretPaths {
                XCTAssertFalse(tool.transferPaths.contains(secret),
                               "\(tool.name) leaks secret path \(secret) into transferPaths")
            }
        }
    }
}
