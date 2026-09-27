import Foundation
import SwiftUI

struct MoveInsight: Codable, Sendable {
    var bestMove: String?
    var beforeScore: Int?
    var afterScore: Int?
    var beforeWDL: [Int]?
    var afterWDL: [Int]?
}

struct PostMoveReview: Sendable {
    let played: String
    let best: String
    let matched: Bool
    let position: ChessBoard
    let analysis: EngineReply
}

struct SavedMove: Codable, Identifiable, Sendable {
    var id = UUID()
    var uci: String
    var san: String
    var insight: MoveInsight? = nil
}

struct SavedGame: Codable, Identifiable, Sendable {
    var id = UUID()
    var startedAt = Date()
    var updatedAt = Date()
    var opponentElo: Int
    var assisted: Bool
    var liveHelp = false
    var moves: [SavedMove] = []
    var result: String? = nil
    var ratingApplied = false
    var title: String { "Stockfish · \(opponentElo)" }

    init(opponentElo: Int, assisted: Bool) {
        self.opponentElo = opponentElo
        self.assisted = assisted
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, updatedAt, opponentElo, assisted, liveHelp, moves, result, ratingApplied
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startedAt = try values.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? startedAt
        opponentElo = try values.decodeIfPresent(Int.self, forKey: .opponentElo) ?? 1400
        assisted = try values.decodeIfPresent(Bool.self, forKey: .assisted) ?? false
        liveHelp = try values.decodeIfPresent(Bool.self, forKey: .liveHelp) ?? false
        moves = try values.decodeIfPresent([SavedMove].self, forKey: .moves) ?? []
        result = try values.decodeIfPresent(String.self, forKey: .result)
        ratingApplied = try values.decodeIfPresent(Bool.self, forKey: .ratingApplied) ?? false
    }
}

struct LocalData: Codable {
    var rating = 1200
    var opponentElo = 1400
    var enginePath = EngineRunner.detectedPath()
    var codexPath = CodexCoach.detectedPath()
    var coachEnabled = false
    var games: [SavedGame] = []
}

enum GameStorage {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LearnChess", isDirectory: true)
    }
    static var url: URL { directory.appendingPathComponent("games.json") }
    static func load() -> LocalData {
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(LocalData.self, from: data) else { return LocalData() }
        return decoded
    }
    static func save(_ value: LocalData) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

@MainActor final class GameModel: ObservableObject {
    @Published var data: LocalData
    @Published var activeID: UUID?
    @Published var cursor = 0
    @Published var board = ChessBoard.initial
    @Published var selectedSquare: Int?
    @Published var promotionChoices: [ChessMove] = []
    @Published var analysis: EngineReply?
    @Published var postMoveReview: PostMoveReview?
    @Published var isReviewVisible = false
    @Published var coachAnswer = ""
    @Published var coachQuestion = ""
    @Published var isThinking = false
    @Published var isAnalyzing = false
    @Published var isAsking = false
    @Published var message: String?
    @Published var panel: Panel = .play
    @Published var isFocusMode = false
    @Published var sidebarCollapsed = false
    private let autosave: Bool
    enum Panel: String, CaseIterable { case play = "Play", library = "Library", settings = "Settings" }

    init(data: LocalData? = nil, autosave: Bool = true) {
        self.data = data ?? GameStorage.load()
        self.autosave = autosave
        if let game = self.data.games.max(by: { $0.updatedAt < $1.updatedAt }) { open(game.id) }
        else { newGame() }
    }

    var activeIndex: Int? { data.games.firstIndex { $0.id == activeID } }
    var game: SavedGame? { activeIndex.map { data.games[$0] } }
    var isAtEnd: Bool { cursor == (game?.moves.count ?? 0) }
    var canPlay: Bool { isAtEnd && board.turn == .white && game?.result == nil && !isThinking }
    var canRequestHint: Bool { game?.liveHelp == true && canPlay && !isAnalyzing }
    var canAnalyzePosition: Bool { game?.liveHelp == true || game?.result != nil }
    var canUseCoach: Bool { data.coachEnabled && canAnalyzePosition }
    var hasEngine: Bool { FileManager.default.isExecutableFile(atPath: data.enginePath) }
    var legalTargets: Set<Int> {
        guard let selectedSquare else { return [] }
        return Set(board.legalMoves.filter { $0.from == selectedSquare }.map(\.to))
    }

    func persist() {
        guard autosave else { return }
        do { try GameStorage.save(data) } catch { message = "Could not save games: \(error.localizedDescription)" }
    }

    func newGame() {
        let new = SavedGame(opponentElo: data.opponentElo, assisted: false)
        data.games.insert(new, at: 0)
        activeID = new.id
        cursor = 0
        board = .initial
        selectedSquare = nil
        promotionChoices = []
        analysis = nil
        postMoveReview = nil
        isReviewVisible = false
        coachAnswer = ""
        isThinking = false
        panel = .play
        persist()
    }

    func open(_ id: UUID) {
        guard let index = data.games.firstIndex(where: { $0.id == id }) else { return }
        activeID = id
        cursor = data.games[index].moves.count
        reconstructBoard()
        panel = .play
        coachAnswer = ""
        analysis = nil
        postMoveReview = nil
        isReviewVisible = false
        isThinking = false
        promotionChoices = []
        if data.games[index].result == nil && board.turn == .black { resumeEngineTurn() }
    }

    func go(to ply: Int) {
        cursor = max(0, min(ply, game?.moves.count ?? 0))
        reconstructBoard()
        analysis = nil
        postMoveReview = nil
        isReviewVisible = false
        selectedSquare = nil
        promotionChoices = []
    }

    private func reconstructBoard() {
        var next = ChessBoard.initial
        for stored in (game?.moves.prefix(cursor) ?? ArraySlice<SavedMove>()) {
            if let move = ChessBoard.move(stored.uci) { _ = next.apply(move) }
        }
        board = next
    }

    func select(_ square: Int) {
        guard canPlay else { return }
        if let selectedSquare, legalTargets.contains(square) {
            let candidates = board.legalMoves.filter { $0.from == selectedSquare && $0.to == square }
            if candidates.count > 1 { promotionChoices = candidates }
            else if let move = candidates.first { makeHumanMove(move) }
            self.selectedSquare = nil
        } else if board.squares[square]?.side == .white {
            selectedSquare = square
        } else { selectedSquare = nil }
    }

    func promote(to kind: Kind) {
        guard let move = promotionChoices.first(where: { $0.promotion == kind }) else { return }
        promotionChoices = []
        makeHumanMove(move)
    }

    private func append(_ move: ChessMove, insight: MoveInsight? = nil) {
        guard let index = activeIndex else { return }
        let san = board.san(for: move)
        guard board.apply(move) else { return }
        data.games[index].moves.append(SavedMove(uci: move.uci, san: san, insight: insight))
        data.games[index].updatedAt = Date()
        cursor = data.games[index].moves.count
        if let result = board.outcome {
            data.games[index].result = result
            applyRatingIfNeeded(at: index)
        }
        persist()
    }

    private func applyRatingIfNeeded(at index: Int) {
        guard let result = data.games[index].result, !data.games[index].ratingApplied else { return }
        data.games[index].ratingApplied = true
        guard !data.games[index].assisted else { return }
        let score = result == "1-0" ? 1.0 : result == "0-1" ? 0.0 : 0.5
        let expected = 1 / (1 + pow(10.0, Double(data.games[index].opponentElo - data.rating) / 400))
        data.rating = max(100, data.rating + Int((32 * (score - expected)).rounded()))
    }

    private func makeHumanMove(_ move: ChessMove) {
        guard hasEngine else { message = EngineError.unavailable.localizedDescription; return }
        let beforeMoves = game?.moves.map(\.uci) ?? []
        let beforeBoard = board
        let isAssisted = game?.liveHelp == true
        append(move)
        guard game?.result == nil else { return }
        isThinking = true
        analysis = nil
        postMoveReview = nil
        isReviewVisible = false
        let afterMoves = game?.moves.map(\.uci) ?? []
        let enginePath = data.enginePath
        let opponentElo = game?.opponentElo ?? data.opponentElo
        let id = activeID
        Task {
            do {
                var review: (EngineReply, MoveInsight)?
                if isAssisted {
                    do {
                        review = try await Task.detached {
                            let before = try EngineRunner.search(path: enginePath, moves: beforeMoves, elo: nil)
                            let after = try EngineRunner.search(path: enginePath, moves: afterMoves, elo: nil)
                            let insight = MoveInsight(bestMove: before.bestMove, beforeScore: before.scoreCentipawns,
                                                      afterScore: after.scoreCentipawns.map { -$0 }, beforeWDL: before.wdl,
                                                      afterWDL: after.wdl.map { [$0[2], $0[1], $0[0]] })
                            return (before, insight)
                        }.value
                    } catch { message = "Move review unavailable: \(error.localizedDescription)" }
                }
                if activeID == id, let review, let index = activeIndex, let last = data.games[index].moves.indices.last {
                    data.games[index].moves[last].insight = review.1
                    persist()
                }
                let reply = try await Task.detached { try EngineRunner.search(path: enginePath, moves: afterMoves, elo: opponentElo, milliseconds: 900) }.value
                guard activeID == id else { return }
                guard game?.moves.map(\.uci) == afterMoves, let uci = reply.bestMove,
                      let move = ChessBoard.move(uci) else { throw EngineError.noMove }
                let playedSAN = game?.moves.last?.san ?? "Your move"
                let playedUCI = game?.moves.last?.uci
                cursor = game?.moves.count ?? 0
                reconstructBoard()
                append(move)
                isThinking = false
                if game?.liveHelp == true, let before = review?.0, let bestUCI = before.bestMove {
                    let bestSAN = ChessBoard.move(bestUCI).map { beforeBoard.san(for: $0) } ?? bestUCI
                    postMoveReview = PostMoveReview(played: playedSAN, best: playedUCI == bestUCI ? playedSAN : bestSAN,
                                                    matched: playedUCI == bestUCI, position: beforeBoard, analysis: before)
                }
            } catch {
                isThinking = false
                message = error.localizedDescription
            }
        }
    }

    private func resumeEngineTurn() {
        guard hasEngine, !isThinking, board.turn == .black else { return }
        let moves = game?.moves.map(\.uci) ?? []
        let beforeMoves = Array(moves.dropLast())
        var beforeBoard = ChessBoard.initial
        for uci in beforeMoves {
            if let move = ChessBoard.move(uci) { _ = beforeBoard.apply(move) }
        }
        let id = activeID
        let path = data.enginePath
        let elo = game?.opponentElo ?? data.opponentElo
        let showReview = game?.liveHelp == true
        isThinking = true
        Task {
            do {
                let before: EngineReply? = showReview ? try? await Task.detached {
                    try EngineRunner.search(path: path, moves: beforeMoves, elo: nil)
                }.value : nil
                let reply = try await Task.detached { try EngineRunner.search(path: path, moves: moves, elo: elo, milliseconds: 900) }.value
                guard activeID == id else { return }
                guard game?.moves.map(\.uci) == moves, let uci = reply.bestMove,
                      let move = ChessBoard.move(uci) else { throw EngineError.noMove }
                let playedSAN = game?.moves.last?.san ?? "Your move"
                let playedUCI = game?.moves.last?.uci
                cursor = game?.moves.count ?? 0
                reconstructBoard()
                append(move)
                isThinking = false
                if game?.liveHelp == true, let before, let bestUCI = before.bestMove {
                    let bestSAN = ChessBoard.move(bestUCI).map { beforeBoard.san(for: $0) } ?? bestUCI
                    postMoveReview = PostMoveReview(played: playedSAN, best: playedUCI == bestUCI ? playedSAN : bestSAN,
                                                    matched: playedUCI == bestUCI, position: beforeBoard, analysis: before)
                }
            } catch {
                isThinking = false
                message = error.localizedDescription
            }
        }
    }

    func toggleAssistance() {
        guard let index = activeIndex else { return }
        if data.games[index].liveHelp {
            data.games[index].liveHelp = false
            analysis = nil
            postMoveReview = nil
            isReviewVisible = false
            coachAnswer = ""
            if !isAtEnd { go(to: data.games[index].moves.count) }
        } else {
            data.games[index].assisted = true
            data.games[index].liveHelp = true
        }
        persist()
    }

    func requestAnalysis() {
        guard canAnalyzePosition else { return }
        guard hasEngine, !isAnalyzing else { if !hasEngine { message = EngineError.unavailable.localizedDescription }; return }
        let moves = game?.moves.prefix(cursor).map(\.uci) ?? []
        let enginePath = data.enginePath
        let id = activeID
        isAnalyzing = true
        Task {
            do {
                let result = try await Task.detached { try EngineRunner.search(path: enginePath, moves: moves, elo: nil, milliseconds: 1100) }.value
                if activeID == id && canAnalyzePosition && game?.moves.prefix(cursor).map(\.uci) == moves { analysis = result }
            } catch { message = error.localizedDescription }
            isAnalyzing = false
        }
    }

    func askCoach(_ shortcut: String? = nil) {
        guard canUseCoach else { message = "Enable live help to use the coach during a game, or finish the game first."; return }
        guard !isAsking else { return }
        let question = shortcut ?? coachQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard let game else { return }
        if let index = activeIndex { data.games[index].assisted = true; persist() }
        let history = game.moves.prefix(cursor).enumerated().map { "\($0.offset + 1). \($0.element.san) [\($0.element.uci)]" }.joined(separator: "\n")
        let inspectedCount = postMoveReview == nil ? cursor : min(cursor + 1, game.moves.count)
        let insights = game.moves.prefix(inspectedCount).compactMap { move -> String? in
            guard let info = move.insight else { return nil }
            return "\(move.san): best=\(info.bestMove ?? "unknown"), before_cp=\(info.beforeScore.map(String.init) ?? "unknown"), after_cp=\(info.afterScore.map(String.init) ?? "unknown"), before_wdl=\(info.beforeWDL?.map(String.init).joined(separator: "/") ?? "unknown"), after_wdl=\(info.afterWDL?.map(String.init).joined(separator: "/") ?? "unknown")"
        }.joined(separator: "\n")
        let prompt = """
        You are a concise chess coach. The user plays White against Stockfish. Explain ideas in plain language. Do not invent engine scores or claim a move is a mistake solely because it differs from the top engine move. Current-position Stockfish values are from the side to move. Saved before/after centipawn scores and WDL values are normalized to White's perspective; WDL is per mille (win/draw/loss). Give 2-4 practical sentences, then one concrete next idea.

        Question: \(question)
        Current board FEN: \(board.fen)
        Most recent move review: \(postMoveReview.map { "played \($0.played), engine preferred \($0.best)" } ?? "none")
        Moves so far (SAN and UCI):
        \(history.isEmpty ? "Starting position" : history)
        Current full strength engine: best=\(analysis?.bestMove ?? "unavailable"), score=\(analysis?.scoreText ?? "unavailable") from side to move, WDL=\(analysis?.wdl?.map(String.init).joined(separator: "/") ?? "unavailable") per mille, PV=\(analysis?.principalVariation.joined(separator: " ") ?? "unavailable")
        Saved move comparisons:
        \(insights.isEmpty ? "None" : insights)
        """
        let path = data.codexPath
        coachAnswer = ""
        isAsking = true
        Task {
            do {
                let response = try await Task.detached { try CodexCoach.ask(path: path, prompt: prompt, workingDirectory: GameStorage.directory) }.value
                coachAnswer = response
            } catch { message = error.localizedDescription }
            isAsking = false
        }
    }
}
