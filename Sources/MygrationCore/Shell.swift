import Foundation

public struct ShellResult {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var ok: Bool { status == 0 }
    public var lines: [String] {
        stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

/// Run a command through zsh. The Ledger only ever READS the machine, so every
/// caller of this in MygrationCore must be side-effect free by construction.
@discardableResult
public func sh(_ command: String, cwd: String? = nil) -> ShellResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-c", command]
    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch {
        return ShellResult(status: 127, stdout: "", stderr: "\(error)")
    }
    // read before waitUntilExit to avoid pipe-buffer deadlock on large output
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return ShellResult(
        status: p.terminationStatus,
        stdout: String(data: outData, encoding: .utf8) ?? "",
        stderr: String(data: errData, encoding: .utf8) ?? "")
}
