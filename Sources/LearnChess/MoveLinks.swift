import Foundation

enum MoveLinks {
    private static let pattern = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9])(\\d+)(\\.{1,3})[ \\t]*(O-O-O|O-O|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?)[+#]?(?![A-Za-z0-9])"
    )

    static func attributed(_ answer: String, moves: [SavedMove]) -> AttributedString {
        let source = answer as NSString
        let matches = pattern.matches(in: answer, range: NSRange(location: 0, length: source.length))
        var markdown = ""
        var position = 0
        for match in matches {
            guard let ply = ply(for: match, source: source, moves: moves) else { continue }
            markdown += source.substring(with: NSRange(location: position, length: match.range.location - position))
            markdown += "[\(source.substring(with: match.range))](learnchess://move/\(ply))"
            position = NSMaxRange(match.range)
        }
        markdown += source.substring(from: position)
        return (try? AttributedString(markdown: markdown,
                                      options: .init(interpretedSyntax: .full,
                                                     failurePolicy: .returnPartiallyParsedIfPossible)))
            ?? AttributedString(answer)
    }

    static func ply(from url: URL) -> Int? {
        guard url.scheme == "learnchess", url.host == "move",
              let ply = Int(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), ply > 0 else { return nil }
        return ply
    }

    private static func ply(for match: NSTextCheckingResult, source: NSString, moves: [SavedMove]) -> Int? {
        guard let turn = Int(source.substring(with: match.range(at: 1))), turn > 0 else { return nil }
        let dots = source.substring(with: match.range(at: 2))
        let ply = (turn - 1) * 2 + (dots.count == 3 ? 2 : 1)
        guard moves.indices.contains(ply - 1) else { return nil }
        let reference = source.substring(with: NSRange(location: match.range(at: 3).location,
                                                       length: NSMaxRange(match.range) - match.range(at: 3).location))
        let normalized = reference.trimmingCharacters(in: CharacterSet(charactersIn: "+#"))
        let actual = moves[ply - 1].san.trimmingCharacters(in: CharacterSet(charactersIn: "+#"))
        return normalized == actual ? ply : nil
    }
}
