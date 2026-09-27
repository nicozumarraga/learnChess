import Foundation

@main struct ModelCheck {
    @MainActor static func main() async {
        var initial = LocalData()
        initial.games = []
        check(!initial.enginePath.isEmpty, "Stockfish installed for live-help check")

        let model = GameModel(data: initial, autosave: false)
        model.toggleAssistance()
        check(model.game?.liveHelp == true, "live help enabled")
        check(model.analysis == nil, "no automatic pre-move arrow")

        model.select(ChessBoard.square("e2")!)
        model.select(ChessBoard.square("e4")!)
        await waitUntil { !model.isThinking }
        check(model.game?.moves.count == 2, "human and Stockfish moves completed")
        check(model.analysis == nil, "last-move review does not draw on main board")
        check(model.postMoveReview != nil, "last-move comparison prepared")
        check(!model.isReviewVisible, "last-move arrow waits for explicit request")
        check(model.isAtEnd && model.canPlay, "main board stays playable")

        model.isReviewVisible = true
        check(model.canPlay, "review board does not block the main board")
        model.requestAnalysis()
        await waitUntil { !model.isAnalyzing }
        check(model.analysis != nil && model.canPlay, "hint arrow does not block moves")

        guard let next = model.board.legalMoves.first(where: { $0.promotion == nil }) else {
            fail("next legal move exists")
        }
        model.select(next.from)
        model.select(next.to)
        await waitUntil { !model.isThinking }
        check(model.game?.moves.count == 4, "move accepted after hint and review arrows")
        check(model.analysis == nil, "old hint clears after moving")

        model.toggleAssistance()
        check(!model.canAnalyzePosition, "unassisted live game hides analysis")
        model.requestAnalysis()
        check(model.analysis == nil, "unassisted game cannot reveal hint")
    }

    @MainActor private static func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(20)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        check(condition(), "background engine work finished")
    }

    private static func check(_ value: Bool, _ label: String) {
        guard value else { fail(label) }
        print("PASS: \(label)")
    }

    private static func fail(_ label: String) -> Never {
        fputs("FAIL: \(label)\n", stderr)
        exit(1)
    }
}
