import SwiftUI

/// Simple filled silhouettes designed to remain readable on a small board.
struct ChessPieceShape: Shape {
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func polygon(_ points: [CGPoint]) {
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

        switch kind {
        case .pawn:
            path.addEllipse(in: CGRect(x: 37, y: 10, width: 26, height: 26))
            path.move(to: p(42, 36))
            path.addQuadCurve(to: p(29, 75), control: p(39, 51))
            path.addLine(to: p(71, 75))
            path.addQuadCurve(to: p(58, 36), control: p(61, 51))
            path.closeSubpath()
            path.addRoundedRect(in: CGRect(x: 24, y: 72, width: 52, height: 11), cornerSize: CGSize(width: 4, height: 4))
            path.addRoundedRect(in: CGRect(x: 19, y: 82, width: 62, height: 8), cornerSize: CGSize(width: 3, height: 3))
        case .rook:
            polygon([p(22, 15), p(34, 15), p(34, 26), p(44, 26), p(44, 15), p(56, 15), p(56, 26), p(66, 26), p(66, 15), p(78, 15), p(75, 37), p(25, 37)])
            polygon([p(31, 37), p(69, 37), p(66, 74), p(34, 74)])
            path.addRoundedRect(in: CGRect(x: 24, y: 71, width: 52, height: 11), cornerSize: CGSize(width: 3, height: 3))
            path.addRoundedRect(in: CGRect(x: 18, y: 81, width: 64, height: 9), cornerSize: CGSize(width: 3, height: 3))
        case .knight:
            path.move(to: p(31, 76))
            path.addLine(to: p(32, 61))
            path.addQuadCurve(to: p(18, 52), control: p(24, 59))
            path.addLine(to: p(13, 40))
            path.addLine(to: p(26, 32))
            path.addLine(to: p(30, 17))
            path.addLine(to: p(38, 24))
            path.addLine(to: p(50, 12))
            path.addQuadCurve(to: p(75, 35), control: p(76, 16))
            path.addQuadCurve(to: p(65, 62), control: p(69, 52))
            path.addLine(to: p(68, 76))
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: 30, y: 39, width: 6, height: 6))
            path.addRoundedRect(in: CGRect(x: 22, y: 75, width: 56, height: 10), cornerSize: CGSize(width: 3, height: 3))
            path.addRoundedRect(in: CGRect(x: 18, y: 84, width: 64, height: 7), cornerSize: CGSize(width: 3, height: 3))
        case .bishop:
            path.move(to: p(50, 9))
            path.addQuadCurve(to: p(72, 39), control: p(73, 20))
            path.addQuadCurve(to: p(56, 65), control: p(71, 53))
            path.addLine(to: p(44, 65))
            path.addQuadCurve(to: p(28, 39), control: p(29, 53))
            path.addQuadCurve(to: p(50, 9), control: p(27, 20))
            path.closeSubpath()
            path.addRoundedRect(in: CGRect(x: 29, y: 64, width: 42, height: 12), cornerSize: CGSize(width: 4, height: 4))
            path.addRoundedRect(in: CGRect(x: 21, y: 76, width: 58, height: 12), cornerSize: CGSize(width: 4, height: 4))
        case .queen:
            polygon([p(20, 32), p(29, 47), p(31, 20), p(44, 43), p(50, 12), p(56, 43), p(69, 20), p(71, 47), p(80, 32), p(72, 71), p(28, 71)])
            path.addRoundedRect(in: CGRect(x: 26, y: 68, width: 48, height: 10), cornerSize: CGSize(width: 4, height: 4))
            path.addRoundedRect(in: CGRect(x: 19, y: 78, width: 62, height: 11), cornerSize: CGSize(width: 4, height: 4))
        case .king:
            polygon([p(44, 12), p(56, 12), p(56, 24), p(66, 24), p(66, 34), p(56, 34), p(56, 43), p(72, 47), p(68, 73), p(32, 73), p(28, 47), p(44, 43), p(44, 34), p(34, 34), p(34, 24), p(44, 24)])
            path.addRoundedRect(in: CGRect(x: 27, y: 70, width: 46, height: 10), cornerSize: CGSize(width: 4, height: 4))
            path.addRoundedRect(in: CGRect(x: 20, y: 80, width: 60, height: 10), cornerSize: CGSize(width: 4, height: 4))
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 100))
    }
}

struct ChessPieceView: View {
    let piece: Piece

    var body: some View {
        ChessPieceShape(kind: piece.kind)
            .fill(piece.side == .white ? Color(red: 0.98, green: 0.98, blue: 0.96) : Color(red: 0.29, green: 0.30, blue: 0.29))
            .overlay {
                ChessPieceShape(kind: piece.kind)
                    .stroke(piece.side == .white ? Color(red: 0.38, green: 0.39, blue: 0.37) : Color(red: 0.13, green: 0.14, blue: 0.13), lineWidth: 2.2)
            }
            .shadow(color: .black.opacity(0.22), radius: 1, y: 2)
            .accessibilityLabel("\(piece.side.rawValue) \(piece.kind.rawValue)")
    }
}
