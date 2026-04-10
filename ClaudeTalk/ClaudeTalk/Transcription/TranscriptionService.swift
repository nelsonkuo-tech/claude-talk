import Foundation

class TranscriptionService {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var isReady = false
    private let transcribeLock = NSLock()
    private var readyMarkerPath: String
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 2

    private var executablePath: String
    private var language: String?

    init(language: String? = nil) {
        self.language = language
        self.readyMarkerPath = NSTemporaryDirectory() + "claude-talk-ready-\(ProcessInfo.processInfo.processIdentifier)"

        let bundle = Bundle.main
        let resourcePath = bundle.resourcePath ?? ""

        // Look for bundled binary (onedir) first, then fall back to script
        let bundledBinary = "\(resourcePath)/transcribe_server_dist/transcribe_server"
        let bundledScript = "\(resourcePath)/transcribe_server.py"

        if FileManager.default.fileExists(atPath: bundledBinary) {
            executablePath = bundledBinary
        } else if FileManager.default.fileExists(atPath: bundledScript) {
            executablePath = bundledScript
        } else {
            executablePath = ""
        }
    }

    var isAvailable: Bool {
        return !executablePath.isEmpty && FileManager.default.fileExists(atPath: executablePath)
    }

    func start() -> Bool {
        guard isAvailable else {
            NSLog("[ClaudeTalk] TranscriptionService: not available")
            return false
        }

        // Clean up old marker
        try? FileManager.default.removeItem(atPath: readyMarkerPath)

        NSLog("[ClaudeTalk] TranscriptionService: starting %@", executablePath)

        let proc = Process()

        if executablePath.hasSuffix(".py") {
            let pythonPath = FileManager.default.fileExists(atPath: "/usr/bin/python3")
                ? "/usr/bin/python3" : "/opt/homebrew/bin/python3"
            proc.executableURL = URL(fileURLWithPath: pythonPath)
            proc.arguments = ["-u", executablePath]
        } else {
            proc.executableURL = URL(fileURLWithPath: executablePath)
        }

        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_TALK_MODEL_SIZE"] = "base"
        env["CLAUDE_TALK_COMPUTE"] = "int8"
        env["CLAUDE_TALK_LANGUAGE"] = language ?? ""
        env["CLAUDE_TALK_READY_FILE"] = readyMarkerPath
        proc.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        // Log stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                NSLog("[ClaudeTalk] transcribe_server: %@", str.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        do {
            try proc.run()
        } catch {
            NSLog("[ClaudeTalk] TranscriptionService: failed to start: %@", error.localizedDescription)
            return false
        }

        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading

        // Wait for ready marker file (up to 30 seconds)
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 30 {
            if FileManager.default.fileExists(atPath: readyMarkerPath) {
                isReady = true
                NSLog("[ClaudeTalk] TranscriptionService: daemon ready (%.1fs)",
                      Date().timeIntervalSince(startTime))
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        NSLog("[ClaudeTalk] TranscriptionService: timeout waiting for daemon")
        proc.terminate()
        return false
    }

    func transcribe(wavPath: String, promptHint: String? = nil) -> String? {
        transcribeLock.lock()
        defer { transcribeLock.unlock() }

        if let process = process, !process.isRunning {
            NSLog("[ClaudeTalk] TranscriptionService: daemon died, restarting...")
            restart()
        }

        guard let process = process, process.isRunning,
              let stdin = stdinHandle, let stdout = stdoutHandle else {
            NSLog("[ClaudeTalk] TranscriptionService: daemon not running")
            return nil
        }

        var command = wavPath
        if let hint = promptHint, !hint.isEmpty {
            command += "\t" + hint
        }
        command += "\n"
        stdin.write(command.data(using: .utf8)!)

        // Read response line
        var result = Data()
        let startTime = Date()

        while true {
            let chunk = stdout.availableData
            if chunk.isEmpty {
                // EOF - process died
                NSLog("[ClaudeTalk] TranscriptionService: daemon EOF, restarting...")
                consecutiveFailures += 1
                restart()
                return nil
            }
            result.append(chunk)

            if let str = String(data: result, encoding: .utf8), str.contains("\n") {
                let text = str.trimmingCharacters(in: .whitespacesAndNewlines)
                let elapsed = Date().timeIntervalSince(startTime)
                NSLog("[ClaudeTalk] TranscriptionService: transcribed in %.2fs: %@", elapsed, text)

                // Detect stale daemon: instant empty response means pipe is broken
                if text.isEmpty && elapsed < 0.05 {
                    consecutiveFailures += 1
                    NSLog("[ClaudeTalk] TranscriptionService: suspect stale daemon (%d/%d)",
                          consecutiveFailures, maxConsecutiveFailures)
                    if consecutiveFailures >= maxConsecutiveFailures {
                        NSLog("[ClaudeTalk] TranscriptionService: restarting stale daemon...")
                        restart()
                    }
                    return nil
                }

                consecutiveFailures = 0
                return text.isEmpty ? nil : text
            }

            if Date().timeIntervalSince(startTime) > 15 {
                NSLog("[ClaudeTalk] TranscriptionService: timeout, restarting...")
                consecutiveFailures += 1
                restart()
                return nil
            }
        }
    }

    private func restart() {
        NSLog("[ClaudeTalk] TranscriptionService: restarting daemon...")
        stop()
        consecutiveFailures = 0
        if start() {
            NSLog("[ClaudeTalk] TranscriptionService: daemon restarted successfully")
        } else {
            NSLog("[ClaudeTalk] TranscriptionService: daemon restart FAILED")
        }
    }

    func stop() {
        if let stdin = stdinHandle {
            let quit = "QUIT\n"
            stdin.write(quit.data(using: .utf8)!)
        }
        process?.terminate()
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        isReady = false
        try? FileManager.default.removeItem(atPath: readyMarkerPath)
    }

    deinit {
        stop()
    }
}
