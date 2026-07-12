import Foundation

/// The catalog: where each AI tool keeps its state, what's secret, what must be
/// re-pulled instead of copied, and how to re-auth. This is Mygration's moat —
/// meant to grow via community contribution (like Homebrew's formulae).
/// Paths are relative to $HOME.
public struct AgentTool: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var paths: [String]         // dirs/files that hold this tool's state
    public var secretPaths: [String]   // hold credentials → encrypted lane only, never plain git
    public var regenerate: [String]    // re-pull/rebuild on the new Mac, never transfer (models, caches)
    public var reauth: String?         // one-liner to re-authenticate on the target
    public var pathKeyed: Bool         // state keyed by absolute path → needs re-keying on restore
    /// Curated subset actually safe to copy (memory/skills/config) — excludes
    /// caches, session transcripts, and secrets. Defaults to `paths` minus the
    /// secret/regenerate paths.
    public var transferPaths: [String]

    public init(id: String, name: String, paths: [String], secretPaths: [String] = [],
                regenerate: [String] = [], reauth: String? = nil, pathKeyed: Bool = false,
                transferPaths: [String]? = nil) {
        self.id = id; self.name = name; self.paths = paths; self.secretPaths = secretPaths
        self.regenerate = regenerate; self.reauth = reauth; self.pathKeyed = pathKeyed
        self.transferPaths = transferPaths ?? paths.filter { p in
            !secretPaths.contains(p) && !regenerate.contains(p) }
    }
}

public enum AgentCatalog {
    public static let all: [AgentTool] = [
        AgentTool(id: "claude-code", name: "Claude Code",
                  paths: [".claude", ".claude.json"],
                  secretPaths: [".claude.json"],            // MCP servers embed tokens
                  reauth: "claude  (OAuth → Keychain)", pathKeyed: true,
                  // curated: the brain, not the caches/transcripts (which can hold secrets)
                  transferPaths: [".claude/memory", ".claude/skills", ".claude/agents",
                                  ".claude/plugins", ".claude/CLAUDE.md", ".claude/settings.json",
                                  ".claude/projects"]),
        AgentTool(id: "codex", name: "OpenAI Codex CLI",
                  paths: [".codex"], secretPaths: [".codex/auth.json"],
                  reauth: "codex login"),
        AgentTool(id: "gemini", name: "Gemini CLI",
                  paths: [".gemini"], secretPaths: [".gemini/oauth_creds.json"],
                  reauth: "gemini  (Google sign-in)"),
        AgentTool(id: "gcloud", name: "Google Cloud SDK",
                  paths: [".config/gcloud"], secretPaths: [".config/gcloud"],
                  reauth: "gcloud auth login"),
        AgentTool(id: "qwen", name: "Qwen Code",
                  paths: [".qwen"], secretPaths: [".qwen"], reauth: "qwen login"),
        AgentTool(id: "grok", name: "Grok CLI (xAI)",
                  paths: [".grok", ".config/grok"], secretPaths: [".config/grok"],
                  reauth: "export XAI_API_KEY=…"),
        AgentTool(id: "kimi", name: "Kimi (Moonshot)",
                  paths: [".kimi", ".config/kimi"], secretPaths: [".config/kimi"]),
        AgentTool(id: "llama", name: "Meta Llama",
                  paths: [".llama"], regenerate: [".llama/checkpoints"],
                  reauth: "llama model download"),
        AgentTool(id: "ollama", name: "Ollama",
                  paths: [".ollama"],
                  regenerate: [".ollama/models"],           // GBs of weights — re-pull, never copy
                  reauth: "ollama pull <model>"),
        AgentTool(id: "copilot", name: "GitHub Copilot CLI",
                  paths: [".copilot", ".config/github-copilot"],
                  secretPaths: [".config/github-copilot/apps.json"],
                  reauth: "gh auth login / copilot"),
        AgentTool(id: "cursor", name: "Cursor",
                  paths: [".cursor"], pathKeyed: true),
        AgentTool(id: "windsurf", name: "Windsurf / Codeium",
                  paths: [".windsurf", ".codeium"], secretPaths: [".codeium"]),
        AgentTool(id: "amazon-q", name: "Amazon Q",
                  paths: [".aws/amazonq"], secretPaths: [".aws/amazonq"],
                  reauth: "q login"),
        AgentTool(id: "aider", name: "Aider",
                  paths: [".aider.conf.yml"], secretPaths: [".aider.conf.yml"]),
        AgentTool(id: "continue", name: "Continue",
                  paths: [".continue"], secretPaths: [".continue/config.json"]),
    ]
}

/// What discovery found on a given machine for one catalog entry.
public struct DiscoveredAgent: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var foundPaths: [String]   // which catalog paths actually exist here
    public var bytes: Int
    public var hasSecrets: Bool
    public var regenerateOnly: Bool   // everything present is re-pull-not-copy (e.g. Ollama models)
    public var reauth: String?
    public var pathKeyed: Bool
    public var transferPaths: [String]   // curated roots that exist here, safe to copy
}
