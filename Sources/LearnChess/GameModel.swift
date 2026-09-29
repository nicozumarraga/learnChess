import Foundation
import SwiftUI

struct MoveInsight: Codable, Sendable {
    var bestMove: String?
    var beforeScore: Int?
    var afterScore: Int?
    var beforeWDL: [Int]?
    var afterWDL: [Int]?
    var quality: MoveQuality? = nil
}

enum MoveQuality: String, Codable, Sendable {
    case brilliant, great, best, good, inaccuracy, mistake, blunder

    var title: String { rawValue.capitalized }

    static func judge(played: String, best: String?, loss: Int, wasSacrifice: Bool, wasUnderPressure: Bool) -> Self {
        if loss >= 300 { return .blunder }
        if loss >= 150 { return .mistake }
        if loss >= 65 { return .inaccuracy }
        if played == best {
            if wasSacrifice && loss <= 20 { return .brilliant }
            if wasUnderPressure && loss <= 20 { return .great }
            return .best
        }
        return .good
    }
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

struct CoachTurn: Codable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
}

struct PracticeLine: Sendable {
    let id = UUID()
    let gameID: UUID
    let originPly: Int
    let side: Side
    let startingMoves: [String]
    let bestMove: ChessMove
    let bestSAN: String
    var board: ChessBoard
    var moves: [SavedMove] = []
    var selectedSquare: Int? = nil
    var promotionChoices: [ChessMove] = []
    var isThinking = false
    var error: String? = nil
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
    var ratingChange: Int? = nil
    var analysisComplete = false
    var postGameSummary: String? = nil
    var coachTurns: [CoachTurn] = []
    var title: String { "Stockfish · \(opponentElo)" }

    init(opponentElo: Int, assisted: Bool) {
        self.opponentElo = opponentElo
        self.assisted = assisted
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, updatedAt, opponentElo, assisted, liveHelp, moves, result, ratingApplied, ratingChange, analysisComplete, postGameSummary, coachTurns
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
        ratingChange = try values.decodeIfPresent(Int.self, forKey: .ratingChange)
        analysisComplete = try values.decodeIfPresent(Bool.self, forKey: .analysisComplete) ?? false
        postGameSummary = try values.decodeIfPresent(String.self, forKey: .postGameSummary)
        coachTurns = try values.decodeIfPresent([CoachTurn].self, forKey: .coachTurns) ?? []
    }
}

struct LocalData: Codable {
    var rating = 1200
    var opponentElo = 1400
    var enginePath = EngineRunner.detectedPath()
    var codexPath = CodexCoach.detectedPath()
    var coachEnabled = false
    var games: [SavedGame] = []
    var ratingPolicyVersion = 1

    init() {}

    private enum CodingKeys: String, CodingKey {
        case rating, opponentElo, enginePath, codexPath, coachEnabled, games, ratingPolicyVersion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rating = try values.decodeIfPresent(Int.self, forKey: .rating) ?? 1200
        opponentElo = try values.decodeIfPresent(Int.self, forKey: .opponentElo) ?? 1400
        enginePath = try values.decodeIfPresent(String.self, forKey: .enginePath) ?? EngineRunner.detectedPath()
        codexPath = try values.decodeIfPresent(String.self, forKey: .codexPath) ?? CodexCoach.detectedPath()
        coachEnabled = try values.decodeIfPresent(Bool.self, forKey: .coachEnabled) ?? false
        games = try values.decodeIfPresent([SavedGame].self, forKey: .games) ?? []
        ratingPolicyVersion = try values.decodeIfPresent(Int.self, forKey: .ratingPolicyVersion) ?? 0
    }
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
    @Published var coachQuestion = ""
    @Published var practice: PracticeLine?
    @Published var isThinking = false
    @Published var isAnalyzing = false
    @Published var isAsking = false
    @Published var analyzingGameID: UUID?
    @Published var analysisProgress = ""
    @Published var replayMove: ChessMove?
    @Published var replayCaption = ""
    @Published var message: String?
    @Published var panel: Panel = .play
    @Published var isFocusMode = false
    @Published var sidebarCollapsed = false
    private let autosave: Bool
    private var replayToken = UUID()
    enum Panel: String, CaseIterable { case play = "Play", library = "Library", settings = "Settings" }

    init(data: LocalData? = nil, autosave: Bool = true) {
        self.data = data ?? GameStorage.load()
        self.autosave = autosave
        reconcileRatingPolicy()
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
    var isPostGameAnalyzing: Bool { analyzingGameID == activeID }
    var displayedBoard: ChessBoard { practice?.board ?? board }
    var captureLedger: CaptureLedger {
        let moves = practice.map { $0.startingMoves + $0.moves.map(\.uci) }
            ?? game?.moves.prefix(cursor).map(\.uci) ?? []
        return CaptureLedger(moves: moves)
    }

    private func reconcileRatingPolicy() {
        guard data.ratingPolicyVersion < 1 else { return }
        for index in data.games.indices.sorted(by: { data.games[$0].startedAt < data.games[$1].startedAt }) {
            let game = data.games[index]
            let usedLiveHelp = game.liveHelp || game.moves.contains(where: { $0.insight != nil })
            if game.assisted, usedLiveHelp, game.ratingApplied, let result = game.result {
                let previous = data.rating
                data.rating = updatedRating(after: result, against: game.opponentElo)
                data.games[index].ratingChange = data.rating - previous
            }
        }
        data.ratingPolicyVersion = 1
        persist()
    }

    private func updatedRating(after result: String, against elo: Int) -> Int {
        let score = result == "1-0" ? 1.0 : result == "0-1" ? 0.0 : 0.5
        let expected = 1 / (1 + pow(10.0, Double(elo - data.rating) / 400))
        return max(100, data.rating + Int((32 * (score - expected)).rounded()))
    }
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
        practice = nil
        coachQuestion = ""
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
        practice = nil
        coachQuestion = ""
        analysis = nil
        postMoveReview = nil
        isReviewVisible = false
        isThinking = false
        promotionChoices = []
        if data.games[index].result == nil && board.turn == .black { resumeEngineTurn() }
        if data.games[index].result != nil { startPostGameAnalysisIfNeeded() }
    }

    func go(to ply: Int) {
        practice = nil
        replayToken = UUID()
        replayMove = nil
        replayCaption = ""
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
        if data.games[index].result != nil { startPostGameAnalysisIfNeeded() }
    }

    private func applyRatingIfNeeded(at index: Int) {
        guard let result = data.games[index].result, !data.games[index].ratingApplied else { return }
        data.games[index].ratingApplied = true
        let previous = data.rating
        data.rating = updatedRating(after: result, against: data.games[index].opponentElo)
        data.games[index].ratingChange = data.rating - previous
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
            coachQuestion = ""
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

    func replay(_ ply: Int) {
        guard let game, game.moves.indices.contains(ply - 1),
              let move = ChessBoard.move(game.moves[ply - 1].uci) else { return }
        go(to: ply - 1)
        let token = replayToken
        let caption = "\((ply + 1) / 2)\(ply.isMultiple(of: 2) ? "..." : ".")\(game.moves[ply - 1].san)"
        replayCaption = "Before \(caption)"
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard replayToken == token else { return }
            go(to: ply)
            replayToken = token
            replayMove = move
            replayCaption = "After \(caption)"
            try? await Task.sleep(for: .seconds(2))
            if replayToken == token { replayMove = nil; replayCaption = "" }
        }
    }

    func startPostGameAnalysisIfNeeded() {
        guard let game, game.result != nil, analyzingGameID == nil else { return }
        let needsEngine = !game.analysisComplete
        let needsCoach = data.coachEnabled && game.postGameSummary == nil &&
            FileManager.default.isExecutableFile(atPath: data.codexPath)
        guard needsEngine || needsCoach else { return }
        let id = game.id
        let moves = game.moves
        let result = game.result ?? "1/2-1/2"
        let enginePath = data.enginePath
        let codexPath = data.codexPath
        analyzingGameID = id
        analysisProgress = needsEngine ? "Analyzing moves with Stockfish…" : "Writing game review with Codex…"
        Task {
            do {
                if needsEngine {
                    guard FileManager.default.isExecutableFile(atPath: enginePath) else { throw EngineError.unavailable }
                    var board = ChessBoard.initial
                    var prefix: [String] = []
                    var before = try await Task.detached {
                        try EngineRunner.search(path: enginePath, moves: [], elo: nil, milliseconds: 500)
                    }.value
                    var insights: [MoveInsight] = []
                    for (offset, saved) in moves.enumerated() {
                        guard let move = ChessBoard.move(saved.uci) else { throw EngineError.noMove }
                        let piece = board.squares[move.from]
                        let best = before.bestMove
                        guard board.apply(move) else { throw EngineError.noMove }
                        let sacrifice = best == saved.uci &&
                            [Kind.knight, .bishop, .rook, .queen].contains(piece?.kind ?? .pawn) &&
                            board.legalMoves.contains(where: { $0.to == move.to })
                        prefix.append(saved.uci)
                        let after: EngineReply
                        if offset == moves.count - 1 {
                            let whiteScore = result == "1-0" ? 10_000 : result == "0-1" ? -10_000 : 0
                            after = EngineReply(bestMove: nil,
                                                scoreCentipawns: board.turn == .white ? whiteScore : -whiteScore,
                                                wdl: board.turn == .white ? terminalWDL(result) : Array(terminalWDL(result).reversed()))
                        } else {
                            let current = prefix
                            after = try await Task.detached {
                                try EngineRunner.search(path: enginePath, moves: current, elo: nil, milliseconds: 500)
                            }.value
                        }
                        let beforeCP = effectiveScore(before)
                        let afterCP = effectiveScore(after)
                        let loss = max(0, (beforeCP ?? 0) + (afterCP ?? 0))
                        let moverIsWhite = offset.isMultiple(of: 2)
                        let quality = MoveQuality.judge(played: saved.uci, best: best, loss: loss,
                                                        wasSacrifice: sacrifice,
                                                        wasUnderPressure: (beforeCP ?? 0) < -100)
                        insights.append(MoveInsight(bestMove: best,
                                                    beforeScore: beforeCP.map { moverIsWhite ? $0 : -$0 },
                                                    afterScore: afterCP.map { moverIsWhite ? -$0 : $0 },
                                                    beforeWDL: before.wdl.map { moverIsWhite ? $0 : [$0[2], $0[1], $0[0]] },
                                                    afterWDL: after.wdl.map { moverIsWhite ? [$0[2], $0[1], $0[0]] : $0 },
                                                    quality: quality))
                        before = after
                        analysisProgress = "Analyzing move \(offset + 1) of \(moves.count)…"
                    }
                    if let index = data.games.firstIndex(where: { $0.id == id }) {
                        for offset in insights.indices where data.games[index].moves.indices.contains(offset) {
                            data.games[index].moves[offset].insight = insights[offset]
                        }
                        data.games[index].analysisComplete = true
                        persist()
                    }
                }
                if needsCoach, let index = data.games.firstIndex(where: { $0.id == id }) {
                    analysisProgress = "Writing game review with Codex…"
                    let finished = data.games[index]
                    let history = finished.moves.enumerated().map { offset, move in
                        let prefix = "\(offset / 2 + 1)\(offset.isMultiple(of: 2) ? "." : "...")"
                        return "\(prefix)\(move.san) [\(move.uci)] — \(move.insight?.quality?.title ?? "unrated"), before=\(move.insight?.beforeScore.map(String.init) ?? "?"), after=\(move.insight?.afterScore.map(String.init) ?? "?") cp from White's perspective"
                    }.joined(separator: "\n")
                    let prompt = """
                    Review this completed chess game for the White player. Result: \(result). Give a concise game summary, the main turning points, and 2-4 specific lessons. Cite actual moves using exact notation such as 16...Rg8 or 17.Bxh6 so the app can link them to the board. Do not create hyperlinks; the app adds move links. Use only the supplied moves and engine comparisons. The move labels are approximate Stockfish-based heuristics; do not claim certainty about brilliant or great moves. Do not invent variations, scores, or moves.

                    \(history)
                    """
                    let answer = try await Task.detached {
                        try CodexCoach.ask(path: codexPath, prompt: prompt, workingDirectory: GameStorage.directory)
                    }.value
                    if let index = data.games.firstIndex(where: { $0.id == id }) {
                        data.games[index].postGameSummary = answer
                        persist()
                    }
                }
            } catch { message = "Postgame analysis: \(error.localizedDescription)" }
            analyzingGameID = nil
            analysisProgress = ""
        }
    }

    private func terminalWDL(_ result: String) -> [Int] {
        result == "1-0" ? [1000, 0, 0] : result == "0-1" ? [0, 0, 1000] : [0, 1000, 0]
    }

    private func effectiveScore(_ reply: EngineReply) -> Int? {
        if let score = reply.scoreCentipawns { return score }
        if let mate = reply.mate { return mate > 0 ? 10_000 - abs(mate) * 100 : -10_000 + abs(mate) * 100 }
        return nil
    }

    var practiceCanMove: Bool {
        guard let practice else { return false }
        return !practice.isThinking && practice.moves.count < 12 &&
            practice.board.turn == practice.side && practice.board.outcome == nil
    }

    var practiceTargets: Set<Int> {
        guard practiceCanMove, let practice, let square = practice.selectedSquare else { return [] }
        return Set(practice.board.legalMoves.filter { $0.from == square }.map(\.to))
    }

    func startPractice(from ply: Int) {
        guard let game, game.result != nil, game.moves.indices.contains(ply - 1),
              let bestUCI = game.moves[ply - 1].insight?.bestMove,
              let best = ChessBoard.move(bestUCI), hasEngine else { return }
        var position = ChessBoard.initial
        let prefix = game.moves.prefix(ply - 1).map(\.uci)
        for uci in prefix {
            guard let move = ChessBoard.move(uci), position.apply(move) else { return }
        }
        guard position.legalMoves.contains(best) else { return }
        let bestSAN = position.san(for: best)
        var line = PracticeLine(gameID: game.id, originPly: ply, side: .white,
                                startingMoves: prefix, bestMove: best,
                                bestSAN: bestSAN, board: position)
        if position.turn == .black {
            guard line.board.apply(best) else { return }
            line.moves.append(SavedMove(uci: best.uci, san: bestSAN))
        }
        practice = line
        isFocusMode = false
    }

    func bestMoveSAN(for ply: Int) -> String? {
        guard let game, game.moves.indices.contains(ply - 1),
              let uci = game.moves[ply - 1].insight?.bestMove,
              let best = ChessBoard.move(uci) else { return nil }
        var position = ChessBoard.initial
        for saved in game.moves.prefix(ply - 1) {
            guard let move = ChessBoard.move(saved.uci), position.apply(move) else { return nil }
        }
        return position.legalMoves.contains(best) ? position.san(for: best) : nil
    }

    func stopPractice() { practice = nil }

    func practiceSelect(_ square: Int) {
        guard practiceCanMove, var session = practice else { return }
        if let from = session.selectedSquare, practiceTargets.contains(square) {
            let choices = session.board.legalMoves.filter { $0.from == from && $0.to == square }
            session.selectedSquare = nil
            if choices.count > 1 { session.promotionChoices = choices; practice = session }
            else if let move = choices.first { makePracticeMove(move) }
        } else {
            session.selectedSquare = session.board.squares[square]?.side == session.side ? square : nil
            practice = session
        }
    }

    func practicePromote(to kind: Kind) {
        guard let move = practice?.promotionChoices.first(where: { $0.promotion == kind }) else { return }
        practice?.promotionChoices = []
        makePracticeMove(move)
    }

    func cancelPracticePromotion() { practice?.promotionChoices = [] }

    func practiceSuggestedMove() {
        guard let practice, practice.moves.isEmpty else { return }
        makePracticeMove(practice.bestMove)
    }

    private func makePracticeMove(_ move: ChessMove) {
        guard practiceCanMove, var session = practice else { return }
        let san = session.board.san(for: move)
        guard session.board.apply(move) else { return }
        session.moves.append(SavedMove(uci: move.uci, san: san))
        session.selectedSquare = nil
        session.promotionChoices = []
        if session.board.outcome != nil || session.moves.count >= 12 {
            practice = session
            return
        }
        session.isThinking = true
        let id = session.id
        let expectedMoves = session.moves.map(\.uci)
        let allMoves = session.startingMoves + expectedMoves
        let path = data.enginePath
        practice = session
        Task {
            do {
                let reply = try await Task.detached {
                    try EngineRunner.search(path: path, moves: allMoves, elo: nil, milliseconds: 700)
                }.value
                guard var current = practice, current.id == id,
                      current.moves.map(\.uci) == expectedMoves,
                      let uci = reply.bestMove, let answer = ChessBoard.move(uci) else { return }
                let answerSAN = current.board.san(for: answer)
                guard current.board.apply(answer) else { throw EngineError.noMove }
                current.moves.append(SavedMove(uci: answer.uci, san: answerSAN))
                current.isThinking = false
                practice = current
            } catch {
                if practice?.id == id {
                    practice?.isThinking = false
                    practice?.error = error.localizedDescription
                }
            }
        }
    }

    func clearCoachConversation() {
        guard let index = activeIndex else { return }
        data.games[index].coachTurns = []
        persist()
    }

    func askCoach(_ shortcut: String? = nil) {
        guard canUseCoach else { message = "Enable live help to use the coach during a game, or finish the game first."; return }
        guard !isAsking else { return }
        let question = shortcut ?? coachQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard let game else { return }
        if game.result == nil, let index = activeIndex { data.games[index].assisted = true; persist() }
        let history = game.moves.prefix(cursor).enumerated().map {
            "\($0.offset / 2 + 1)\($0.offset.isMultiple(of: 2) ? "." : "...")\($0.element.san) [\($0.element.uci)]"
        }.joined(separator: "\n")
        var context: [String] = []
        var remaining = 24_000
        for turn in game.coachTurns.reversed() {
            let entry = "\(turn.role == .user ? "User" : "Coach"): \(turn.text)"
            guard entry.count <= remaining else { break }
            context.append(entry)
            remaining -= entry.count
        }
        let conversation = context.reversed().joined(separator: "\n\n")
        let inspectedCount = postMoveReview == nil ? cursor : min(cursor + 1, game.moves.count)
        let insights = game.moves.prefix(inspectedCount).compactMap { move -> String? in
            guard let info = move.insight else { return nil }
            return "\(move.san): best=\(info.bestMove ?? "unknown"), before_cp=\(info.beforeScore.map(String.init) ?? "unknown"), after_cp=\(info.afterScore.map(String.init) ?? "unknown"), before_wdl=\(info.beforeWDL?.map(String.init).joined(separator: "/") ?? "unknown"), after_wdl=\(info.afterWDL?.map(String.init).joined(separator: "/") ?? "unknown")"
        }.joined(separator: "\n")
        let prompt = """
        You are a concise chess coach in an ongoing conversation. The user plays White against Stockfish. Answer the latest question using the prior conversation for references such as "that move". Explain ideas in plain language. Do not invent engine scores or claim a move is a mistake solely because it differs from the top engine move. Current-position Stockfish values are from the side to move. Saved before/after centipawn scores and WDL values are normalized to White's perspective; WDL is per mille (win/draw/loss). Use simple Markdown. Cite actual game moves in numbered SAN notation where useful. Do not create hyperlinks; the app adds move links.

        Earlier postgame review: \(game.postGameSummary.map { String($0.prefix(5_000)) } ?? "none")
        Conversation so far:
        \(conversation.isEmpty ? "No earlier turns." : conversation)

        Latest question: \(question)
        Current board FEN: \(board.fen)
        Most recent move review: \(postMoveReview.map { "played \($0.played), engine preferred \($0.best)" } ?? "none")
        Moves so far (SAN and UCI):
        \(history.isEmpty ? "Starting position" : history)
        Current full strength engine: best=\(analysis?.bestMove ?? "unavailable"), score=\(analysis?.scoreText ?? "unavailable") from side to move, WDL=\(analysis?.wdl?.map(String.init).joined(separator: "/") ?? "unavailable") per mille, PV=\(analysis?.principalVariation.joined(separator: " ") ?? "unavailable")
        Saved move comparisons:
        \(insights.isEmpty ? "None" : insights)
        """
        let path = data.codexPath
        let id = game.id
        let turn = CoachTurn(role: .user, text: question)
        if let index = activeIndex {
            data.games[index].coachTurns.append(turn)
            persist()
        }
        coachQuestion = ""
        isAsking = true
        Task {
            do {
                let response = try await Task.detached { try CodexCoach.ask(path: path, prompt: prompt, workingDirectory: GameStorage.directory) }.value
                if let index = data.games.firstIndex(where: { $0.id == id }) {
                    data.games[index].coachTurns.append(CoachTurn(role: .assistant, text: response))
                    persist()
                }
            } catch {
                if let index = data.games.firstIndex(where: { $0.id == id }) {
                    data.games[index].coachTurns.removeAll(where: { $0.id == turn.id })
                    persist()
                }
                message = error.localizedDescription
            }
            isAsking = false
        }
    }
}
