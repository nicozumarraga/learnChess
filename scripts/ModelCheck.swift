import Foundation

@main struct ModelCheck {
    @MainActor static func main() async {
        check(MoveQuality.judge(played: "e2e4", best: "e2e4", loss: 0, wasSacrifice: false, wasUnderPressure: false) == .best,
              "best move label")
        check(MoveQuality.judge(played: "e2e4", best: "d2d4", loss: 350, wasSacrifice: false, wasUnderPressure: false) == .blunder,
              "blunder label")
        var archived = LocalData()
        archived.ratingPolicyVersion = 0
        var oldWin = SavedGame(opponentElo: 1320, assisted: true)
        oldWin.liveHelp = true
        oldWin.result = "1-0"
        oldWin.ratingApplied = true
        oldWin.analysisComplete = true
        archived.games = [oldWin]
        let migrated = GameModel(data: archived, autosave: false)
        check(migrated.data.rating == 1221 && migrated.data.ratingPolicyVersion == 1,
              "previous assisted win updates local rating once")
        check(migrated.game?.ratingChange == 21, "saved win displays its rating change")
        migrated.newGame()
        check(migrated.data.rating == 1221, "rating migration does not repeat")
        var alreadyRated = LocalData()
        alreadyRated.ratingPolicyVersion = 0
        var coachedAfterGame = SavedGame(opponentElo: 1320, assisted: true)
        coachedAfterGame.result = "1-0"
        coachedAfterGame.ratingApplied = true
        coachedAfterGame.analysisComplete = true
        alreadyRated.games = [coachedAfterGame]
        check(GameModel(data: alreadyRated, autosave: false).data.rating == 1200,
              "postgame coaching does not double-count an old result")

        var citedMoves = Array(repeating: SavedMove(uci: "a2a3", san: "a3"), count: 39)
        citedMoves[31].san = "Rg8"
        citedMoves[32].san = "Bxh6"
        citedMoves[38].san = "Bg7"
        let linked = MoveLinks.attributed("After 16...Rg8, 17.Bxh6 failed; 17.g3 was safer. Later 20.Bg7.", moves: citedMoves)
        let targets = linked.runs.compactMap { $0.link.flatMap(MoveLinks.ply(from:)) }
        check(targets == [32, 33, 39], "only actual saved move references become links")

        var initial = LocalData()
        initial.games = []
        check(!initial.enginePath.isEmpty, "Stockfish installed for live-help check")

        var finished = SavedGame(opponentElo: 1320, assisted: false)
        var position = ChessBoard.initial
        for uci in ["f2f3", "e7e5", "g2g4", "d8h4"] {
            let move = ChessBoard.move(uci)!
            finished.moves.append(SavedMove(uci: uci, san: position.san(for: move)))
            check(position.apply(move), "saved checkmate move is legal")
        }
        finished.result = position.outcome
        var archive = initial
        archive.games = [finished]
        let mockCLI = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/mock-codex")
        try! "#!/bin/sh\ncat >/dev/null\nprintf 'Review 2...Qh4#'\n".write(to: mockCLI, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockCLI.path)
        defer { try? FileManager.default.removeItem(at: mockCLI) }
        archive.coachEnabled = true
        archive.codexPath = mockCLI.path
        let postGame = GameModel(data: archive, autosave: false)
        await waitUntil { postGame.game?.postGameSummary != nil }
        check(postGame.game?.moves.allSatisfy { $0.insight?.quality != nil } == true,
              "completed game receives a label for every move")
        check(postGame.game?.postGameSummary == "Review 2...Qh4#",
              "completed game automatically receives a Codex review")
        let reviewLinks = MoveLinks.attributed(postGame.game?.postGameSummary ?? "", moves: postGame.game?.moves ?? [])
        check(reviewLinks.runs.compactMap { $0.link.flatMap(MoveLinks.ply(from:)) } == [4],
              "postgame review links to the final move")

        try! """
        #!/bin/sh
        prompt=$(cat)
        case "$prompt" in
          *"User: First question"*"Coach: **First answer**"*"Latest question: Follow up"*) printf '**Second answer** after 2...Qh4#';;
          *"Latest question: First question"*) printf '**First answer** after 2...Qh4#';;
          *) printf 'Unexpected conversation context';;
        esac
        """.write(to: mockCLI, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockCLI.path)
        postGame.askCoach("First question")
        await waitUntil { !postGame.isAsking }
        check(postGame.game?.coachTurns.map(\.role) == [.user, .assistant],
              "coach saves the first exchange with the game")
        postGame.askCoach("Follow up")
        await waitUntil { !postGame.isAsking }
        check(postGame.game?.coachTurns.last?.text == "**Second answer** after 2...Qh4#",
              "follow-up receives previous user and coach turns")
        let rendered = MoveLinks.attributed(postGame.game?.coachTurns.last?.text ?? "", moves: postGame.game?.moves ?? [])
        check(String(rendered.characters).contains("Second answer") && !String(rendered.characters).contains("**"),
              "coach Markdown is rendered")
        check(rendered.runs.compactMap { $0.link.flatMap(MoveLinks.ply(from:)) } == [4],
              "move links survive Markdown rendering")
        let restored = try! JSONDecoder().decode(LocalData.self, from: JSONEncoder().encode(postGame.data))
        check(GameModel(data: restored, autosave: false).game?.coachTurns.count == 4,
              "coach conversation survives reopening the game")
        postGame.startPractice(from: 1)
        check(postGame.practice?.bestMove != nil && postGame.practice?.moves.isEmpty == true,
              "practice starts before the reviewed move")
        postGame.practiceSuggestedMove()
        await waitUntil { postGame.practice?.moves.count == 2 && postGame.practice?.isThinking == false }
        check(postGame.game?.moves.count == 4 && postGame.data.rating == 1200,
              "practice reply leaves the saved game and rating untouched")
        postGame.stopPractice()
        check(postGame.practice == nil, "review resumes after practice stops")
        postGame.startPractice(from: 1)
        postGame.practiceSelect(ChessBoard.square("f2")!)
        postGame.practiceSelect(ChessBoard.square("f3")!)
        await waitUntil { postGame.practice?.moves.count == 2 && postGame.practice?.isThinking == false }
        check(postGame.practice?.moves.first?.uci == "f2f3", "practice board accepts a chosen move")
        if let next = postGame.practice?.board.legalMoves.first(where: { $0.promotion == nil }) {
            postGame.practiceSelect(next.from)
            postGame.practiceSelect(next.to)
            await waitUntil { postGame.practice?.moves.count == 4 && postGame.practice?.isThinking == false }
            check(postGame.game?.moves.count == 4, "several practice turns stay separate from the saved game")
        } else { fail("practice has a second legal move") }
        postGame.stopPractice()
        postGame.clearCoachConversation()
        check(postGame.game?.coachTurns.isEmpty == true && postGame.game?.postGameSummary != nil,
              "clearing chat keeps the separate postgame review")

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
