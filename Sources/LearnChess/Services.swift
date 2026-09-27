import Foundation

struct EngineReply: Sendable {
    var bestMove: String?
    var scoreCentipawns: Int?
    var mate: Int?
    var wdl: [Int]?
    var depth: Int = 0
    var principalVariation: [String] = []

    var scoreText: String {
        if let mate { return "Mate \(mate > 0 ? "+" : "")\(mate)" }
        guard let scoreCentipawns else { return "—" }
        return String(format: "%+.2f", Double(scoreCentipawns) / 100)
    }
}

enum EngineError: LocalizedError {
    case unavailable, noMove, failed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "Choose a Stockfish executable in Settings."
        case .noMove: "Stockfish returned no legal move."
        case .failed(let message): "Stockfish could not start: \(message)"
        }
    }
}

enum EngineRunner {
    static func detectedPath() -> String {
        ExecutableLocator.find("stockfish")
    }

    static func search(path: String, moves: [String], elo: Int?, milliseconds: Int = 650) throws -> EngineReply {
        guard FileManager.default.isExecutableFile(atPath: path) else { throw EngineError.unavailable }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.currentDirectoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        do { try process.run() } catch { throw EngineError.failed(error.localizedDescription) }
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        let settings = elo.map { "setoption name UCI_LimitStrength value true\nsetoption name UCI_Elo value \($0)\n" } ?? "setoption name UCI_LimitStrength value false\n"
        let position = "position startpos" + (moves.isEmpty ? "" : " moves " + moves.joined(separator: " "))
        let commands = "uci\n\(settings)setoption name UCI_ShowWDL value true\nisready\n\(position)\ngo movetime \(milliseconds)\n"
        input.fileHandleForWriting.write(Data(commands.utf8))
        var buffer = ""
        var reply = EngineReply()
        while process.isRunning {
            let data = output.fileHandleForReading.availableData
            if data.isEmpty { break }
            buffer += String(decoding: data, as: UTF8.self)
            while let newline = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.hasPrefix("info ") { parseInfo(line, into: &reply) }
                if line.hasPrefix("bestmove ") {
                    let parts = line.split(separator: " ")
                    reply.bestMove = parts.count > 1 && parts[1] != "(none)" ? String(parts[1]) : nil
                    input.fileHandleForWriting.write(Data("quit\n".utf8))
                    return reply
                }
            }
        }
        throw EngineError.noMove
    }

    private static func parseInfo(_ line: String, into reply: inout EngineReply) {
        let tokens = line.split(separator: " ").map(String.init)
        func value(after key: String) -> String? {
            guard let index = tokens.firstIndex(of: key), index + 1 < tokens.count else { return nil }
            return tokens[index + 1]
        }
        guard let depth = Int(value(after: "depth") ?? "0"), depth >= reply.depth,
              tokens.contains("score") else { return }
        reply.depth = depth
        if let scoreIndex = tokens.firstIndex(of: "score"), scoreIndex + 2 < tokens.count {
            if tokens[scoreIndex + 1] == "cp" {
                reply.scoreCentipawns = Int(tokens[scoreIndex + 2]); reply.mate = nil
            } else if tokens[scoreIndex + 1] == "mate" {
                reply.mate = Int(tokens[scoreIndex + 2]); reply.scoreCentipawns = nil
            }
        }
        if let index = tokens.firstIndex(of: "wdl"), index + 3 < tokens.count {
            reply.wdl = tokens[(index + 1)...(index + 3)].compactMap(Int.init)
        }
        if let index = tokens.firstIndex(of: "pv"), index + 1 < tokens.count {
            reply.principalVariation = Array(tokens[(index + 1)...].prefix(8))
        }
    }
}

enum CoachError: LocalizedError {
    case unavailable, failed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "Install Codex CLI and sign in to enable the coach."
        case .failed(let text): text
        }
    }
}

enum CodexCoach {
    static func detectedPath() -> String {
        ExecutableLocator.find("codex")
    }

    static func ask(path: String, prompt: String, workingDirectory: URL) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else { throw CoachError.unavailable }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["exec", "--ephemeral", "--sandbox", "read-only", "--skip-git-repo-check", "-"]
        process.currentDirectoryURL = workingDirectory
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw CoachError.failed(error.localizedDescription) }
        input.fileHandleForWriting.write(Data(prompt.utf8))
        try? input.fileHandleForWriting.close()
        let response = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = String(decoding: response, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            throw CoachError.failed("Codex exited with an error. Check your CLI sign-in with `codex login status`.")
        }
        return result
    }
}

private enum ExecutableLocator {
    static func find(_ name: String) -> String {
        let environment = ProcessInfo.processInfo.environment
        var directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        if let prefix = environment["HOMEBREW_PREFIX"] {
            directories.append(URL(fileURLWithPath: prefix).appendingPathComponent("bin").path)
        }
        directories.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path)
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? ""
    }
}
