import Foundation

enum Side: String, Codable, Sendable {
    case white, black
    var other: Side { self == .white ? .black : .white }
}

enum Kind: String, Codable, Sendable {
    case king = "k", queen = "q", rook = "r", bishop = "b", knight = "n", pawn = "p"
    var symbol: String { rawValue.uppercased() }
    var materialPoints: Int {
        switch self {
        case .pawn: 1
        case .knight, .bishop: 3
        case .rook: 5
        case .queen: 9
        case .king: 0
        }
    }
}

struct Piece: Codable, Equatable, Sendable {
    let side: Side
    let kind: Kind
    var glyph: String {
        let white = ["k": "♔", "q": "♕", "r": "♖", "b": "♗", "n": "♘", "p": "♙"]
        let black = ["k": "♚", "q": "♛", "r": "♜", "b": "♝", "n": "♞", "p": "♟"]
        return (side == .white ? white : black)[kind.rawValue] ?? ""
    }
}

struct ChessMove: Codable, Equatable, Hashable, Sendable {
    let from: Int
    let to: Int
    var promotion: Kind? = nil
    var uci: String {
        ChessBoard.squareName(from) + ChessBoard.squareName(to) + (promotion?.rawValue ?? "")
    }
}

struct CaptureLedger: Sendable {
    private(set) var takenByWhite: [Kind] = []
    private(set) var takenByBlack: [Kind] = []

    init(moves: [String]) {
        var board = ChessBoard.initial
        for uci in moves {
            guard let move = ChessBoard.move(uci), let moving = board.squares[move.from] else { break }
            let victim: Piece?
            if moving.kind == .pawn && board.enPassant == move.to && board.squares[move.to] == nil {
                victim = board.squares[move.to + (moving.side == .white ? -8 : 8)]
            } else {
                victim = board.squares[move.to]
            }
            guard board.apply(move) else { break }
            if let victim {
                if moving.side == .white { takenByWhite.append(victim.kind) }
                else { takenByBlack.append(victim.kind) }
            }
        }
    }

    func taken(by side: Side) -> [Kind] { side == .white ? takenByWhite : takenByBlack }
    func points(by side: Side) -> Int { taken(by: side).reduce(0) { $0 + $1.materialPoints } }
    func lead(for side: Side) -> Int { points(by: side) - points(by: side.other) }
}

struct ChessBoard: Sendable {
    var squares: [Piece?] = Array(repeating: nil, count: 64)
    var turn: Side = .white
    var castling = "KQkq"
    var enPassant: Int? = nil
    var halfmoveClock = 0
    var fullmoveNumber = 1

    static var initial: ChessBoard {
        var board = ChessBoard()
        let back: [Kind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for file in 0..<8 {
            board.squares[file] = Piece(side: .white, kind: back[file])
            board.squares[8 + file] = Piece(side: .white, kind: .pawn)
            board.squares[48 + file] = Piece(side: .black, kind: .pawn)
            board.squares[56 + file] = Piece(side: .black, kind: back[file])
        }
        return board
    }

    static func squareName(_ square: Int) -> String {
        String(UnicodeScalar(97 + square % 8)!) + String(square / 8 + 1)
    }

    static func square(_ name: String) -> Int? {
        let chars = Array(name.utf8)
        guard chars.count == 2, (97...104).contains(chars[0]), (49...56).contains(chars[1]) else { return nil }
        return Int(chars[1] - 49) * 8 + Int(chars[0] - 97)
    }

    static func move(_ uci: String) -> ChessMove? {
        let chars = Array(uci)
        guard chars.count == 4 || chars.count == 5,
              let from = square(String(chars[0...1])), let to = square(String(chars[2...3])) else { return nil }
        let promotion = chars.count == 5 ? Kind(rawValue: String(chars[4])) : nil
        if chars.count == 5 && (promotion == nil || promotion == .king || promotion == .pawn) { return nil }
        return ChessMove(from: from, to: to, promotion: promotion)
    }

    var fen: String {
        var rows: [String] = []
        for rank in (0..<8).reversed() {
            var row = ""
            var blanks = 0
            for file in 0..<8 {
                if let piece = squares[rank * 8 + file] {
                    if blanks > 0 { row += String(blanks); blanks = 0 }
                    let symbol = piece.kind.rawValue
                    row += piece.side == .white ? symbol.uppercased() : symbol
                } else { blanks += 1 }
            }
            if blanks > 0 { row += String(blanks) }
            rows.append(row)
        }
        return "\(rows.joined(separator: "/")) \(turn == .white ? "w" : "b") \(castling.isEmpty ? "-" : castling) \(enPassant.map(Self.squareName) ?? "-") \(halfmoveClock) \(fullmoveNumber)"
    }

    var legalMoves: [ChessMove] {
        pseudoMoves(for: turn).filter { move in
            var copy = self
            copy.applyUnchecked(move)
            return !copy.isInCheck(turn)
        }
    }

    var outcome: String? {
        if legalMoves.isEmpty { return isInCheck(turn) ? (turn == .white ? "0-1" : "1-0") : "1/2-1/2" }
        if halfmoveClock >= 100 { return "1/2-1/2" }
        return nil
    }

    mutating func apply(_ move: ChessMove) -> Bool {
        guard legalMoves.contains(move) else { return false }
        applyUnchecked(move)
        return true
    }

    func san(for move: ChessMove) -> String {
        guard let piece = squares[move.from] else { return move.uci }
        let fromFile = move.from % 8, toFile = move.to % 8
        if piece.kind == .king && abs(toFile - fromFile) == 2 {
            return toFile == 6 ? "O-O" : "O-O-O"
        }
        let capture = squares[move.to] != nil || (piece.kind == .pawn && enPassant == move.to)
        var result = piece.kind == .pawn ? "" : piece.kind.symbol
        if piece.kind != .pawn {
            let others = legalMoves.filter { $0.to == move.to && $0.from != move.from && squares[$0.from]?.kind == piece.kind }
            if !others.isEmpty {
                let fileUnique = others.allSatisfy { $0.from % 8 != fromFile }
                let rankUnique = others.allSatisfy { $0.from / 8 != move.from / 8 }
                if fileUnique || !rankUnique { result += String(UnicodeScalar(97 + fromFile)!) }
                if !fileUnique { result += String(move.from / 8 + 1) }
            }
        } else if capture { result += String(UnicodeScalar(97 + fromFile)!) }
        if capture { result += "x" }
        result += Self.squareName(move.to)
        if let promotion = move.promotion { result += "=\(promotion.symbol)" }
        var next = self
        next.applyUnchecked(move)
        if next.isInCheck(next.turn) { result += next.legalMoves.isEmpty ? "#" : "+" }
        return result
    }

    private mutating func applyUnchecked(_ move: ChessMove) {
        guard let piece = squares[move.from] else { return }
        let capture = squares[move.to] != nil || (piece.kind == .pawn && enPassant == move.to)
        if piece.kind == .pawn && enPassant == move.to && squares[move.to] == nil {
            squares[move.to + (piece.side == .white ? -8 : 8)] = nil
        }
        if piece.kind == .king && abs(move.to - move.from) == 2 {
            let rookFrom = move.to > move.from ? move.from + 3 : move.from - 4
            let rookTo = move.to > move.from ? move.from + 1 : move.from - 1
            squares[rookTo] = squares[rookFrom]
            squares[rookFrom] = nil
        }
        squares[move.to] = Piece(side: piece.side, kind: move.promotion ?? piece.kind)
        squares[move.from] = nil
        for (flag, square) in [("K", 4), ("Q", 4), ("k", 60), ("q", 60), ("K", 7), ("Q", 0), ("k", 63), ("q", 56)] where move.from == square {
            castling.removeAll { String($0) == flag }
        }
        for (flag, square) in [("K", 7), ("Q", 0), ("k", 63), ("q", 56)] where move.to == square {
            castling.removeAll { String($0) == flag }
        }
        enPassant = piece.kind == .pawn && abs(move.to - move.from) == 16 ? (move.to + move.from) / 2 : nil
        halfmoveClock = piece.kind == .pawn || capture ? 0 : halfmoveClock + 1
        if turn == .black { fullmoveNumber += 1 }
        turn = turn.other
    }

    private func pseudoMoves(for side: Side) -> [ChessMove] {
        var result: [ChessMove] = []
        for from in 0..<64 {
            guard let piece = squares[from], piece.side == side else { continue }
            let file = from % 8, rank = from / 8
            func add(_ to: Int) {
                guard (0..<64).contains(to), squares[to]?.side != side, squares[to]?.kind != .king else { return }
                if piece.kind == .pawn && (to / 8 == 0 || to / 8 == 7) {
                    for promotion in [Kind.queen, .rook, .bishop, .knight] { result.append(ChessMove(from: from, to: to, promotion: promotion)) }
                } else { result.append(ChessMove(from: from, to: to)) }
            }
            switch piece.kind {
            case .pawn:
                let step = side == .white ? 1 : -1
                let next = rank + step
                if (0..<8).contains(next) {
                    let forward = next * 8 + file
                    if squares[forward] == nil {
                        add(forward)
                        let start = side == .white ? 1 : 6
                        if rank == start {
                            let double = (rank + step * 2) * 8 + file
                            if squares[double] == nil { add(double) }
                        }
                    }
                    for df in [-1, 1] where (0..<8).contains(file + df) {
                        let target = next * 8 + file + df
                        if squares[target]?.side == side.other || enPassant == target { add(target) }
                    }
                }
            case .knight:
                for (df, dr) in [(1,2),(2,1),(-1,2),(-2,1),(1,-2),(2,-1),(-1,-2),(-2,-1)] {
                    if (0..<8).contains(file + df) && (0..<8).contains(rank + dr) { add((rank + dr) * 8 + file + df) }
                }
            case .king:
                for df in -1...1 { for dr in -1...1 where df != 0 || dr != 0 {
                    if (0..<8).contains(file + df) && (0..<8).contains(rank + dr) { add((rank + dr) * 8 + file + df) }
                }}
                if !isInCheck(side) {
                    let home = side == .white ? 4 : 60
                    if from == home {
                        let kingFlag = side == .white ? "K" : "k"
                        let queenFlag = side == .white ? "Q" : "q"
                        if castling.contains(kingFlag), squares[home + 1] == nil, squares[home + 2] == nil,
                           squares[home + 3] == Piece(side: side, kind: .rook), !isAttacked(home + 1, by: side.other), !isAttacked(home + 2, by: side.other) {
                            add(home + 2)
                        }
                        if castling.contains(queenFlag), squares[home - 1] == nil, squares[home - 2] == nil, squares[home - 3] == nil,
                           squares[home - 4] == Piece(side: side, kind: .rook), !isAttacked(home - 1, by: side.other), !isAttacked(home - 2, by: side.other) {
                            add(home - 2)
                        }
                    }
                }
            case .bishop, .rook, .queen:
                let diagonal = [(1,1),(-1,1),(1,-1),(-1,-1)]
                let straight = [(1,0),(-1,0),(0,1),(0,-1)]
                let directions = piece.kind == .bishop ? diagonal : piece.kind == .rook ? straight : diagonal + straight
                for (df, dr) in directions {
                    var f = file + df, r = rank + dr
                    while (0..<8).contains(f) && (0..<8).contains(r) {
                        let target = r * 8 + f
                        if squares[target]?.side == side { break }
                        add(target)
                        if squares[target] != nil { break }
                        f += df; r += dr
                    }
                }
            }
        }
        return result
    }

    func isInCheck(_ side: Side) -> Bool {
        guard let king = squares.firstIndex(of: Piece(side: side, kind: .king)) else { return true }
        return isAttacked(king, by: side.other)
    }

    private func isAttacked(_ target: Int, by side: Side) -> Bool {
        let file = target % 8, rank = target / 8
        let pawnRank = rank + (side == .white ? -1 : 1)
        if (0..<8).contains(pawnRank) {
            for df in [-1, 1] where (0..<8).contains(file + df) {
                if squares[pawnRank * 8 + file + df] == Piece(side: side, kind: .pawn) { return true }
            }
        }
        for (df, dr) in [(1,2),(2,1),(-1,2),(-2,1),(1,-2),(2,-1),(-1,-2),(-2,-1)] {
            if (0..<8).contains(file + df) && (0..<8).contains(rank + dr),
               squares[(rank + dr) * 8 + file + df] == Piece(side: side, kind: .knight) { return true }
        }
        for df in -1...1 { for dr in -1...1 where df != 0 || dr != 0 {
            if (0..<8).contains(file + df) && (0..<8).contains(rank + dr),
               squares[(rank + dr) * 8 + file + df] == Piece(side: side, kind: .king) { return true }
        }}
        for (df, dr) in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,1),(1,-1),(-1,-1)] {
            var f = file + df, r = rank + dr
            while (0..<8).contains(f) && (0..<8).contains(r) {
                if let piece = squares[r * 8 + f] {
                    if piece.side == side && (piece.kind == .queen || (df == 0 || dr == 0 ? piece.kind == .rook : piece.kind == .bishop)) { return true }
                    break
                }
                f += df; r += dr
            }
        }
        return false
    }
}
