import Foundation

// MARK: - Process helpers

extension LinkModel {
    struct CmdResult {
        var stdout: String
        var stderr: String
        var code: Int32
    }

    /// Run a command to completion and capture its output.
    ///
    /// Use this only for processes that finish on their own. A child that
    /// keeps running, or that leaves a grandchild holding the inherited
    /// pipe, never closes stdout, so reading to EOF here would block
    /// forever. Long-lived processes go through `spawnDetached` instead.
    func runCmd(_ path: String, _ args: [String]) -> CmdResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do { try process.run() } catch { return nil }
        // Read while the process runs: it can block writing once a pipe
        // buffer fills, so draining after waitUntilExit would deadlock.
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CmdResult(
            stdout: String(data: out, encoding: .utf8) ?? "",
            stderr: String(data: err, encoding: .utf8) ?? "",
            code: process.terminationStatus)
    }

    @discardableResult
    func run(_ path: String, _ args: [String]) -> String? {
        runCmd(path, args)?.stdout
    }

    /// Start a process and return without waiting for it.
    ///
    /// Both output streams go to /dev/null. That matters for daemons: if a
    /// long-lived child inherited a pipe, nothing would ever close it, and
    /// discarding the output is cheaper than a reader thread that lives as
    /// long as the child.
    @discardableResult
    func spawnDetached(_ path: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
