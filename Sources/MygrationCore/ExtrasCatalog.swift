import Foundation

/// Things installed OUTSIDE Homebrew that `brew bundle` won't restore: dev tools
/// installed via `curl | bash`, manually-dragged apps, etc. Closes the gap where
/// discovery only saw brew-managed software.
public struct ExtraTool: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String        // "tool" | "app"
    public var reinstall: String   // how to get it on the new Mac
}

struct ExtraDef {
    let id: String, name: String
    let markers: [String]          // HOME-relative dirs that indicate it's installed
    let brewFormula: String?       // if present in brew, it's already covered — skip
    let reinstall: String
}

enum ExtrasCatalog {
    static let tools: [ExtraDef] = [
        .init(id: "nvm", name: "nvm", markers: [".nvm"], brewFormula: "nvm",
              reinstall: "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"),
        .init(id: "pyenv", name: "pyenv", markers: [".pyenv"], brewFormula: "pyenv",
              reinstall: "brew install pyenv"),
        .init(id: "rbenv", name: "rbenv", markers: [".rbenv"], brewFormula: "rbenv",
              reinstall: "brew install rbenv"),
        .init(id: "asdf", name: "asdf", markers: [".asdf"], brewFormula: "asdf",
              reinstall: "brew install asdf"),
        .init(id: "rust", name: "Rust (rustup)", markers: [".rustup", ".cargo"], brewFormula: "rustup",
              reinstall: "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"),
        .init(id: "ohmyzsh", name: "Oh My Zsh", markers: [".oh-my-zsh"], brewFormula: nil,
              reinstall: "sh -c \"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""),
        .init(id: "deno", name: "Deno", markers: [".deno"], brewFormula: "deno",
              reinstall: "curl -fsSL https://deno.land/install.sh | sh"),
        .init(id: "volta", name: "Volta", markers: [".volta"], brewFormula: "volta",
              reinstall: "curl https://get.volta.sh | bash"),
        .init(id: "sdkman", name: "SDKMAN", markers: [".sdkman"], brewFormula: nil,
              reinstall: "curl -s https://get.sdkman.io | bash"),
        .init(id: "fnm", name: "fnm", markers: [".local/share/fnm"], brewFormula: "fnm",
              reinstall: "brew install fnm"),
        .init(id: "cargo-bins", name: "Cargo binaries", markers: [".cargo/bin"], brewFormula: nil,
              reinstall: "cargo install <crate> (re-install your global crates)"),
    ]

    /// Common apps → their Homebrew cask, so we can suggest an exact install
    /// command instead of "do it by hand".
    static let knownCasks: [String: String] = [
        "visual studio code": "visual-studio-code", "google chrome": "google-chrome",
        "firefox": "firefox", "docker": "docker-desktop", "spotify": "spotify",
        "zoom.us": "zoom", "imageoptim": "imageoptim", "tailscale": "tailscale-app",
        "antigravity": "antigravity", "antigravity ide": "antigravity",
        "slack": "slack", "notion": "notion", "figma": "figma", "iterm": "iterm2",
        "iterm2": "iterm2", "arc": "arc", "warp": "warp", "cursor": "cursor",
        "obsidian": "obsidian", "rectangle": "rectangle", "raycast": "raycast",
        "1password": "1password", "postman": "postman", "vlc": "vlc",
    ]
    /// Apps that come from the App Store, not a download.
    static let appStoreApps: Set<String> = ["xcode", "testflight", "developer", "apple developer"]
    /// Helper apps created automatically — not user-installed, skip.
    static let ignoredApps: Set<String> = ["claude code url handler", "zoomlauncher"]

    /// Apple system apps that ship with macOS — never report as "manual installs".
    static let systemApps: Set<String> = [
        "safari", "mail", "messages", "facetime", "music", "podcasts", "tv", "news", "stocks",
        "home", "photos", "maps", "calendar", "contacts", "reminders", "notes", "freeform",
        "clock", "weather", "calculator", "dictionary", "chess", "stickies", "voice memos",
        "image capture", "font book", "preview", "textedit", "quicktime player", "system settings",
        "app store", "automator", "time machine", "photo booth", "mission control", "launchpad",
        "books", "find my", "shortcuts", "iphone mirroring", "passwords", "utilities",
    ]
}
