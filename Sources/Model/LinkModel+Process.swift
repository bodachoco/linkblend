import Foundation

// MARK: - Process helpers

extension LinkModel {
    func isAlive(_ pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0
    }

    struct CmdResult {
        var stdout: String
        var stderr: String
        var code: Int32
    }

    func runCmd(_ path: String, _ args: [String]) -> CmdResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do { try process.run() } catch { return nil }
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
}
