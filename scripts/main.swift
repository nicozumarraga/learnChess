import Foundation

func check(_ value: @autoclosure () -> Bool, _ label: String) {
    guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
    print("PASS: \(label)")
}

var board = ChessBoard.initial
check(board.legalMoves.count == 20, "20 opening moves")
check(board.fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "starting FEN")
let e4 = ChessBoard.move("e2e4")!
check(board.san(for: e4) == "e4", "SAN notation")
check(board.apply(e4), "e4 legal")
check(board.legalMoves.count == 20, "20 black responses")
check(board.enPassant == ChessBoard.square("e3"), "en passant target")

func perft(_ position: ChessBoard, depth: Int) -> Int {
    if depth == 0 { return 1 }
    return position.legalMoves.reduce(0) { total, move in
        var next = position
        _ = next.apply(move)
        return total + perft(next, depth: depth - 1)
    }
}
check(perft(.initial, depth: 3) == 8902, "opening perft depth 3")

board = .initial
for move in ["e2e4", "a7a6", "e4e5", "d7d5"] { check(board.apply(ChessBoard.move(move)!), "play \(move)") }
check(board.apply(ChessBoard.move("e5d6")!), "en passant capture")
check(board.squares[ChessBoard.square("d5")!] == nil, "captured pawn removed")
let enPassantLedger = CaptureLedger(moves: ["e2e4", "a7a6", "e4e5", "d7d5", "e5d6"])
check(enPassantLedger.takenByWhite == [.pawn] && enPassantLedger.points(by: .white) == 1,
      "en passant counts as a captured pawn")
check(enPassantLedger.lead(for: .white) == 1, "capture lead uses piece points")
let exchangeLedger = CaptureLedger(moves: ["e2e4", "d7d5", "e4d5", "d8d5"])
check(exchangeLedger.takenByWhite == [.pawn] && exchangeLedger.takenByBlack == [.pawn],
      "capture display includes both players")
check(exchangeLedger.lead(for: .white) == 0 && exchangeLedger.lead(for: .black) == 0,
      "equal captures clear the material lead")

board = .initial
for move in ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6"] { check(board.apply(ChessBoard.move(move)!), "play \(move)") }
check(board.san(for: ChessBoard.move("e1g1")!) == "O-O", "castling SAN")
check(board.apply(ChessBoard.move("e1g1")!), "castling legal")
check(board.squares[ChessBoard.square("f1")!] == Piece(side: .white, kind: .rook), "rook moved on castle")

board = .initial
for move in ["f2f3", "e7e5", "g2g4", "d8h4"] { check(board.apply(ChessBoard.move(move)!), "play \(move)") }
check(board.outcome == "0-1", "checkmate detected")

board = ChessBoard()
board.squares[ChessBoard.square("e1")!] = Piece(side: .white, kind: .king)
board.squares[ChessBoard.square("e8")!] = Piece(side: .black, kind: .king)
board.squares[ChessBoard.square("a7")!] = Piece(side: .white, kind: .pawn)
board.castling = ""
check(board.legalMoves.filter { $0.from == ChessBoard.square("a7") }.count == 4, "all promotion choices")
check(board.apply(ChessBoard.move("a7a8n")!), "knight underpromotion")
check(board.squares[ChessBoard.square("a8")!] == Piece(side: .white, kind: .knight), "promoted knight placed")

let path = EngineRunner.detectedPath()
if !path.isEmpty {
    let reply = try EngineRunner.search(path: path, moves: [], elo: 1400, milliseconds: 200)
    check(reply.bestMove != nil, "Stockfish replied")
    check(ChessBoard.initial.legalMoves.map(\.uci).contains(reply.bestMove ?? ""), "Stockfish move legal")
    check(reply.wdl?.count == 3, "Stockfish WDL estimate")
    let analysis = try EngineRunner.search(path: path, moves: [], elo: nil, milliseconds: 200)
    check(ChessBoard.initial.legalMoves.map(\.uci).contains(analysis.bestMove ?? ""), "full-strength analysis move legal")
}
