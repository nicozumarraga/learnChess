import AppKit
import SwiftUI

private enum Theme {
    static let background = Color(red: 0.075, green: 0.11, blue: 0.095)
    static let sidebar = Color(red: 0.105, green: 0.15, blue: 0.125)
    static let panel = Color(red: 0.13, green: 0.18, blue: 0.15)
    static let border = Color.white.opacity(0.08)
    static let accent = Color(red: 0.67, green: 0.86, blue: 0.43)
    static let text = Color(red: 0.94, green: 0.95, blue: 0.89)
    static let muted = Color(red: 0.6, green: 0.69, blue: 0.62)
    static let lightSquare = Color(red: 0.93, green: 0.94, blue: 0.82)
    static let darkSquare = Color(red: 0.46, green: 0.60, blue: 0.33)
}

private extension MoveQuality {
    var symbol: String {
        switch self {
        case .brilliant: "sparkles"
        case .great: "star.fill"
        case .best: "checkmark.circle.fill"
        case .good: "checkmark.circle"
        case .inaccuracy: "questionmark.circle.fill"
        case .mistake: "exclamationmark.circle.fill"
        case .blunder: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .brilliant: .cyan
        case .great: .purple
        case .best, .good: Theme.accent
        case .inaccuracy: .yellow
        case .mistake: .orange
        case .blunder: .red
        }
    }
}

@main struct LearnChessApp: App {
    @StateObject private var model = GameModel()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: model.isFocusMode ? 620 : 1060, minHeight: model.isFocusMode ? 470 : 720)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private struct RootView: View {
    @EnvironmentObject var model: GameModel
    private var compactSidebar: Bool { model.sidebarCollapsed || model.isFocusMode }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.border).frame(width: 1)
            Group {
                switch model.panel {
                case .play: PlayView()
                case .library: LibraryView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .alert("LearnChess", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .confirmationDialog("Promote pawn", isPresented: Binding(get: { !model.promotionChoices.isEmpty }, set: { if !$0 { model.promotionChoices = [] } })) {
            Button("Queen") { model.promote(to: .queen) }
            Button("Rook") { model.promote(to: .rook) }
            Button("Bishop") { model.promote(to: .bishop) }
            Button("Knight") { model.promote(to: .knight) }
        }
        .confirmationDialog("Promote in practice", isPresented: Binding(
            get: { model.practice?.promotionChoices.isEmpty == false },
            set: { if !$0 { model.cancelPracticePromotion() } }
        )) {
            Button("Queen") { model.practicePromote(to: .queen) }
            Button("Rook") { model.practicePromote(to: .rook) }
            Button("Bishop") { model.practicePromote(to: .bishop) }
            Button("Knight") { model.practicePromote(to: .knight) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 23) {
            if compactSidebar {
                Button {
                    model.isFocusMode = false
                    model.sidebarCollapsed = false
                } label: {
                    Image(systemName: "sidebar.right").font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Expand sidebar")
                .frame(maxWidth: .infinity)
                .padding(.top, 26)
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "checkerboard.shield.checkmark")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LEARNCHESS").font(.system(size: 14, weight: .heavy, design: .rounded)).tracking(1.2)
                        Text("Your private chess studio").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Button { model.sidebarCollapsed = true } label: { Image(systemName: "sidebar.left") }
                        .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Collapse sidebar")
                }
                .padding(.top, 26)
            }
            VStack(spacing: 8) {
                forEachPanel
            }
            if !compactSidebar {
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR RATING").font(.system(size: 10, weight: .bold)).tracking(1.8).foregroundStyle(Theme.muted)
                    Text("\(model.data.rating)").font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text("Local · completed games").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
            }
            Spacer()
            if !compactSidebar, let game = model.game {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURRENT GAME").font(.system(size: 10, weight: .bold)).tracking(1.8).foregroundStyle(Theme.muted)
                    Text(game.title).font(.system(size: 13, weight: .semibold))
                    Text(game.result ?? "In progress").font(.system(size: 12)).foregroundStyle(Theme.accent)
                }
                .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, compactSidebar ? 7 : 18)
        .frame(width: compactSidebar ? 56 : 224)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.sidebar)
    }

    private var forEachPanel: some View {
        ForEach(GameModel.Panel.allCases, id: \.self) { panel in
            Button {
                model.panel = panel
                if panel != .play { model.isFocusMode = false }
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: panel == .play ? "checkerboard.rectangle" : panel == .library ? "square.stack.3d.up" : "slider.horizontal.3")
                        .frame(width: 20)
                    if !compactSidebar {
                        Text(panel.rawValue)
                        Spacer()
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.panel == panel ? Theme.text : Theme.muted)
                .padding(.horizontal, compactSidebar ? 11 : 14)
                .padding(.vertical, 12)
                .background(model.panel == panel ? Theme.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .help(panel.rawValue)
        }
    }
}

private struct PlayView: View {
    @EnvironmentObject var model: GameModel
    @State private var expandedCategories: Set<MoveQuality> = [.blunder, .mistake]
    var body: some View {
        Group {
            if model.isFocusMode { FocusPlayView() }
            else { standardView }
        }
    }

    private var standardView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Play & improve").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("A quiet place to think one move ahead.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { model.isFocusMode = true } label: { Label("Focus", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(SubtleButton())
                    .fixedSize()
                Button { model.newGame() } label: { Label("New game", systemImage: "plus") }
                    .buttonStyle(AccentButton())
            }
            GeometryReader { space in
              HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 12) {
                    playerStrip(name: "Stockfish", detail: "\(model.game?.opponentElo ?? model.data.opponentElo) Elo", symbol: "cpu", active: model.board.turn == .black)
                    ChessBoardView()
                    if !model.replayCaption.isEmpty {
                        Text(model.replayCaption).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                    playerStrip(name: "You", detail: "\(model.data.rating) local Elo", symbol: "person.fill", active: model.board.turn == .white)
                    HStack(spacing: 10) {
                        Button { model.go(to: 0) } label: { Image(systemName: "backward.end.fill") }
                        Button { model.go(to: model.cursor - 1) } label: { Image(systemName: "chevron.left") }
                        Text("\(model.cursor) / \(model.game?.moves.count ?? 0) plies").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
                            .frame(minWidth: 80)
                        Button { model.go(to: model.cursor + 1) } label: { Image(systemName: "chevron.right") }
                        Button { model.go(to: model.game?.moves.count ?? 0) } label: { Image(systemName: "forward.end.fill") }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            statusCard
                            movesCard.id("moves")
                            analysisCard
                            if model.game?.result != nil { postGameCard }
                            coachCard(scrollToMoves: { withAnimation { scroll.scrollTo("moves", anchor: .top) } })
                        }
                        .padding(.bottom, 24)
                    }
                    .frame(width: 340)
                    .frame(height: space.size.height)
                }
            }
              .frame(height: space.size.height)
            }
        }
        .padding(28)
    }

    private func playerStrip(name: String, detail: String, symbol: String, active: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).frame(width: 38, height: 38)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if active && model.game?.result == nil {
                Circle().fill(Theme.accent).frame(width: 7, height: 7)
                Text(model.isThinking ? "Thinking" : "To move")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 4)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.game?.result == nil ? "GAME IN PROGRESS" : "GAME COMPLETE")
                    .font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(Theme.muted)
                Spacer()
                Text(model.game?.result ?? "Live").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            Text(model.game?.result == nil ? (model.isAtEnd ? (model.isThinking ? "Stockfish is choosing a move…" : model.postMoveReview != nil ? "Your move. Last-move review is ready." : "Your move. Take your time.") : "Reviewing an earlier position") : "Review your game and learn from it.")
                .font(.system(size: 15, weight: .medium))
            if let change = model.game?.ratingChange {
                Text("Local rating \(String(format: "%+d", change)) · now \(model.data.rating)")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            if !model.hasEngine {
                Text("Stockfish is not configured. Set its executable path in Settings.")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
        }
        .cardStyle()
    }

    private var movesCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle("MOVES")
                Spacer()
                Text("\(model.game?.moves.count ?? 0) ply").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            if let moves = model.game?.moves, !moves.isEmpty {
                LazyVGrid(columns: [GridItem(.fixed(26)), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(0..<((moves.count + 1) / 2), id: \.self) { turn in
                        Text("\(turn + 1).").foregroundStyle(Theme.muted)
                        moveCell(moves[turn * 2], ply: turn * 2 + 1)
                        if turn * 2 + 1 < moves.count { moveCell(moves[turn * 2 + 1], ply: turn * 2 + 2) }
                        else { Text("") }
                    }
                }
                .font(.system(size: 13, design: .monospaced))
            } else { Text("Your moves will appear here.").font(.system(size: 12)).foregroundStyle(Theme.muted) }
        }
        .cardStyle()
    }

    private func moveCell(_ move: SavedMove, ply: Int) -> some View {
        Button { model.go(to: ply) } label: {
            HStack(spacing: 4) {
                Text(move.san).foregroundStyle(model.cursor == ply ? Theme.accent : Theme.text)
                if let quality = move.insight?.quality {
                    Image(systemName: quality.symbol).foregroundStyle(quality.color)
                        .help("\(quality.title) · approximate engine label")
                }
            }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(model.cursor == ply ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle("STOCKFISH ANALYSIS")
                Spacer()
                if model.isAnalyzing { ProgressView().controlSize(.small) }
            }
            if model.game?.result == nil {
                Toggle("Live help", isOn: Binding(get: { model.game?.liveHelp == true }, set: { _ in model.toggleAssistance() }))
                    .toggleStyle(.switch).font(.system(size: 13))
            }
            if model.game?.assisted == true {
                Text("Live help was used in this game. Completed games count toward your local rating.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            if model.isPostGameAnalyzing {
                ProgressView(model.analysisProgress).font(.system(size: 11))
            } else if model.game?.analysisComplete == true {
                Text("Move labels are approximate full-strength engine estimates.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            if !model.canAnalyzePosition {
                Text("Hints are off during this game. You can analyze it after it ends.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                if let review = model.postMoveReview {
                    Button(model.isReviewVisible ? "Hide last-move review" : "Review last move") { model.isReviewVisible.toggle() }
                        .buttonStyle(SubtleButton())
                    if model.isReviewVisible {
                        Text(review.matched ? "You found Stockfish’s preferred move: \(review.played)." : "You played \(review.played). Stockfish preferred \(review.best).")
                            .font(.system(size: 12, weight: .medium))
                        ChessBoardView(previewBoard: review.position, previewMove: ChessBoard.move(review.analysis.bestMove ?? ""), interactive: false)
                            .frame(width: 250, height: 250)
                            .frame(maxWidth: .infinity)
                        Text("Earlier position · board remains playable").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                } else if model.game?.liveHelp == true && model.analysis == nil {
                    Text(model.isThinking ? "Comparing your move with full-strength Stockfish…" : "Play normally, or request a hint before moving.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                if let analysis = model.analysis {
                    HStack(alignment: .firstTextBaseline) {
                        Text(analysis.scoreText).font(.system(size: 27, weight: .semibold, design: .rounded)).foregroundStyle(Theme.accent)
                        Spacer()
                        Text("Depth \(analysis.depth)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    HStack {
                        Text("Best move").foregroundStyle(Theme.muted)
                        Spacer()
                        Text(analysis.bestMove ?? "—").font(.system(size: 13, design: .monospaced))
                    }.font(.system(size: 12))
                    if let wdl = analysis.wdl, wdl.count == 3 {
                        HStack {
                            Text("W / D / L").foregroundStyle(Theme.muted)
                            Spacer()
                            Text("\(wdl[0] / 10)% / \(wdl[1] / 10)% / \(wdl[2] / 10)%")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .font(.system(size: 12))
                        Text("For the side to move · engine estimate").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }
                if model.canRequestHint {
                    Button("Show hint") { model.requestAnalysis() }
                        .buttonStyle(SubtleButton())
                } else if model.game?.result != nil || (!model.isAtEnd && model.postMoveReview == nil) {
                    Button("Analyze this position") { model.requestAnalysis() }
                        .buttonStyle(SubtleButton())
                        .disabled(model.isAnalyzing)
                }
                if let previous = model.game?.moves.prefix(model.cursor).last(where: { $0.insight != nil }), let info = previous.insight, model.postMoveReview == nil {
                    Divider().overlay(Theme.border)
                    Text("MOVE REVIEW").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Theme.muted)
                    Text("\(previous.san) · engine preferred \(info.bestMove ?? "—")")
                        .font(.system(size: 12))
                }
            }
        }
        .cardStyle()
    }

    private var postGameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("POSTGAME MOVE REVIEW")
            if model.isPostGameAnalyzing && model.game?.analysisComplete != true {
                ProgressView(model.analysisProgress).font(.system(size: 11))
            } else if model.game?.analysisComplete == true, let moves = model.game?.moves {
                ForEach([MoveQuality.blunder, .mistake, .inaccuracy, .good, .best, .great, .brilliant], id: \.self) { quality in
                    let entries = moves.enumerated().filter { $0.element.insight?.quality == quality }
                    DisclosureGroup(isExpanded: Binding(
                        get: { expandedCategories.contains(quality) },
                        set: { if $0 { expandedCategories.insert(quality) } else { expandedCategories.remove(quality) } }
                    )) {
                        if entries.isEmpty {
                            Text("None").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        } else {
                            ForEach(entries, id: \.element.id) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 10) {
                                        Button { model.replay(entry.offset + 1) } label: {
                                            Text("\(entry.offset / 2 + 1)\(entry.offset.isMultiple(of: 2) ? "." : "...")\(entry.element.san)")
                                                .font(.system(size: 12, design: .monospaced))
                                        }
                                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                                        if quality == .blunder {
                                            Button("Try line") { model.startPractice(from: entry.offset + 1) }
                                                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(Theme.accent)
                                        }
                                    }
                                    if quality == .blunder, let best = model.bestMoveSAN(for: entry.offset + 1) {
                                        Text("Best: \(best)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                    }
                                    if model.practice?.originPly == entry.offset + 1 {
                                        practiceView
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: quality.symbol).foregroundStyle(quality.color)
                            Text(quality.title).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(entries.count)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Text("Labels are approximate Stockfish estimates.").font(.system(size: 10)).foregroundStyle(Theme.muted)
            } else {
                Text("Engine review will start when Stockfish is available.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .cardStyle()
    }

    private var practiceView: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let practice = model.practice {
                Text("PRACTICE LINE · YOU PLAY \(practice.side == .white ? "WHITE" : "BLACK")")
                    .font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(Theme.muted)
                Text(practice.moves.isEmpty ? "Try \(practice.bestSAN), or choose another move." :
                     practice.isThinking ? "Stockfish is replying…" :
                     practice.moves.count >= 12 || practice.board.outcome != nil ? "Line complete. Restart or return to the review." :
                     "Play another move, or return to the review.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text)
                ChessBoardView(previewBoard: practice.board,
                               previewMove: practice.moves.isEmpty ? practice.bestMove : nil,
                               interactive: false,
                               onSquareTap: { model.practiceSelect($0) },
                               highlightedSquare: practice.selectedSquare,
                               targetSquares: model.practiceTargets)
                    .frame(width: 250, height: 250)
                    .frame(maxWidth: .infinity)
                if !practice.moves.isEmpty {
                    Text(practice.moves.map(\.san).joined(separator: "  "))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                }
                if let error = practice.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
                HStack(spacing: 12) {
                    if practice.moves.isEmpty {
                        Button("Play \(practice.bestSAN)") { model.practiceSuggestedMove() }
                            .disabled(!model.practiceCanMove)
                    } else {
                        Button("Restart line") { model.startPractice(from: practice.originPly) }
                    }
                    Button("Stop practice") { model.stopPractice() }
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                Text("Up to six moves each · this line does not change the saved game or rating.")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
        .padding(10)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
    }

    private func coachCard(scrollToMoves: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("CODEX COACH")
                Spacer()
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            }
            if model.game?.postGameSummary != nil || model.game?.coachTurns.isEmpty == false {
                Button("Back to moves ↑", action: scrollToMoves)
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            if let summary = model.game?.postGameSummary {
                Text("POSTGAME REVIEW").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Theme.muted)
                linkedAnswer(summary)
            } else if model.isPostGameAnalyzing && model.game?.result != nil {
                ProgressView(model.analysisProgress).font(.system(size: 11))
            }
            if let turns = model.game?.coachTurns, !turns.isEmpty {
                HStack {
                    Text("CONVERSATION").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Clear chat") { model.clearCoachConversation() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        .disabled(model.isAsking)
                }
                ForEach(turns) { turn in
                    if turn.role == .user {
                        Text(turn.text)
                            .font(.system(size: 12, weight: .medium))
                            .padding(11).frame(maxWidth: .infinity, alignment: .trailing)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
                    } else {
                        linkedAnswer(turn.text)
                    }
                }
            }
            if model.isAsking { ProgressView("Thinking with Codex…").font(.system(size: 12)) }
            Text("Ask about the position, a move, or your plan.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            ForEach(["Explain the best move", "Why was my last move weak?", "Analyze this board", "Review my earlier mistakes"], id: \.self) { question in
                Button(question) { model.askCoach(question) }
                    .buttonStyle(SubtleButton())
                    .disabled(!model.canUseCoach || model.isAsking)
            }
            HStack {
                TextField("Ask your own question…", text: $model.coachQuestion)
                    .textFieldStyle(.plain)
                    .onSubmit { model.askCoach() }
                Button { model.askCoach() } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .disabled(!model.canUseCoach || model.isAsking)
            }
            .padding(10)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
            if !model.data.coachEnabled {
                Text("Enable the coach in Settings.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            } else if !model.canUseCoach {
                Text("Coach opens with live help or after the game.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .cardStyle()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(Theme.muted)
    }

    private func linkedAnswer(_ answer: String) -> some View {
        Text(MoveLinks.attributed(answer, moves: model.game?.moves ?? []))
            .font(.system(size: 12)).lineSpacing(4).textSelection(.enabled)
            .tint(Theme.accent)
            .environment(\.openURL, OpenURLAction { url in
                guard let ply = MoveLinks.ply(from: url) else { return .systemAction }
                model.replay(ply)
                return .handled
            })
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct FocusPlayView: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                HStack {
                    Text("STOCKFISH").font(.system(size: 11, weight: .bold)).tracking(1.2)
                    Text("\(model.game?.opponentElo ?? model.data.opponentElo)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Spacer()
                    if model.isThinking { ProgressView().controlSize(.small) }
                }
                ChessBoardView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.replayCaption.isEmpty {
                    Text(model.replayCaption).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                }
                HStack {
                    Text("YOU").font(.system(size: 11, weight: .bold)).tracking(1.2)
                    Text("\(model.data.rating)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(model.game?.result ?? (model.board.turn == .white ? "Your move" : "Thinking…"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 14) {
                Button { model.isFocusMode = false } label: {
                    Label("Exit focus", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                Text("MOVE \((model.cursor + 1) / 2)")
                    .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Theme.muted)
                Text(model.isThinking ? "Stockfish is thinking" : model.game?.result == nil ? "Find your best move" : "Game complete")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                HStack(spacing: 12) {
                    Button { model.go(to: model.cursor - 1) } label: { Image(systemName: "chevron.left") }
                    Button { model.go(to: model.cursor + 1) } label: { Image(systemName: "chevron.right") }
                    Button { model.go(to: model.game?.moves.count ?? 0) } label: { Image(systemName: "forward.end.fill") }
                    Spacer()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .font(.system(size: 12))
                Divider().overlay(Theme.border)
                Text("RECENT MOVES").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Theme.muted)
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        if let moves = model.game?.moves {
                            ForEach(Array(moves.enumerated().suffix(12)), id: \.element.id) { item in
                                let index = item.offset
                                let move = item.element
                                Button { model.go(to: index + 1) } label: {
                                    HStack {
                                        Text("\((index / 2) + 1)\(index.isMultiple(of: 2) ? "." : "…")")
                                            .foregroundStyle(Theme.muted)
                                        Text(move.san).foregroundStyle(model.cursor == index + 1 ? Theme.accent : Theme.text)
                                        if let quality = move.insight?.quality {
                                            Image(systemName: quality.symbol).foregroundStyle(quality.color)
                                                .help("\(quality.title) · approximate engine label")
                                        }
                                        Spacer()
                                    }
                                    .font(.system(size: 12, design: .monospaced))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let review = model.postMoveReview {
                    Divider().overlay(Theme.border)
                    Button(model.isReviewVisible ? "Hide review" : "Review last move") { model.isReviewVisible.toggle() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    if model.isReviewVisible {
                        Text(review.matched ? "You found the best move." : "\(review.played) → \(review.best)")
                            .font(.system(size: 12, weight: .medium))
                        ChessBoardView(previewBoard: review.position, previewMove: ChessBoard.move(review.analysis.bestMove ?? ""), interactive: false)
                            .frame(width: 144, height: 144)
                    }
                }
                if let analysis = model.analysis {
                    Divider().overlay(Theme.border)
                    Text("BEST MOVE").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Theme.muted)
                    Text(analysis.bestMove ?? "—")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent)
                    Text(analysis.scoreText).font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else if model.canRequestHint {
                    Button { model.requestAnalysis() } label: { Label("Show hint", systemImage: "arrow.up.right") }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .disabled(model.isAnalyzing)
                } else if model.game?.result != nil {
                    Button("Analyze position") { model.requestAnalysis() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                } else if model.game?.liveHelp == true {
                    Text(model.isThinking ? "Analyzing your move…" : "No hint shown.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                } else {
                    Text("Hints are off.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                if !model.hasEngine {
                    Text("Set Stockfish path in Settings.").font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            .padding(14)
            .frame(width: 176)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(14)
    }
}

private struct ChessBoardView: View {
    @EnvironmentObject var model: GameModel
    var previewBoard: ChessBoard? = nil
    var previewMove: ChessMove? = nil
    var interactive = true
    var onSquareTap: ((Int) -> Void)? = nil
    var highlightedSquare: Int? = nil
    var targetSquares: Set<Int> = []

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let tile = size / 8
            let displayedBoard = previewBoard ?? model.board
            VStack(spacing: 0) {
                ForEach((0..<8).reversed(), id: \.self) { rank in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { file in
                            let square = rank * 8 + file
                            Button {
                                if let onSquareTap { onSquareTap(square) }
                                else if interactive { model.select(square) }
                            } label: {
                                ZStack {
                                    Rectangle().fill((rank + file).isMultiple(of: 2) ? Theme.darkSquare : Theme.lightSquare)
                                    if (onSquareTap != nil ? highlightedSquare == square : interactive && model.selectedSquare == square) {
                                        Rectangle().fill(Color.yellow.opacity(0.35))
                                    }
                                    if (onSquareTap != nil ? targetSquares.contains(square) : interactive && model.legalTargets.contains(square)) {
                                        Circle().fill(Color.black.opacity(0.23)).frame(width: tile * 0.24)
                                    }
                                    if let piece = displayedBoard.squares[square] {
                                        ChessPieceView(piece: piece)
                                            .frame(width: tile * 0.79, height: tile * 0.79)
                                    }
                                    if file == 0 {
                                        Text("\(rank + 1)").font(.system(size: 10, weight: .bold))
                                            .foregroundStyle((rank + file).isMultiple(of: 2) ? Theme.lightSquare : Theme.darkSquare)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                            .padding(4)
                                    }
                                    if rank == 0 {
                                        Text(String(UnicodeScalar(97 + file)!)).font(.system(size: 10, weight: .bold))
                                            .foregroundStyle((rank + file).isMultiple(of: 2) ? Theme.lightSquare : Theme.darkSquare)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                            .padding(4)
                                    }
                                }
                                .frame(width: tile, height: tile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            .frame(width: size, height: size)
            .overlay {
                if let move = previewBoard == nil ? (model.replayMove ?? ChessBoard.move(model.analysis?.bestMove ?? "")) : previewMove,
                   displayedBoard.legalMoves.contains(move) {
                    BestMoveArrow(move: move, isKnight: displayedBoard.squares[move.from]?.kind == .knight, size: size)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct BestMoveArrow: View {
    let move: ChessMove
    let isKnight: Bool
    let size: CGFloat

    var body: some View {
        let tile = size / 8
        let start = point(for: move.from, tile: tile)
        let end = point(for: move.to, tile: tile)
        let bend = abs(end.x - start.x) > abs(end.y - start.y)
            ? CGPoint(x: end.x, y: start.y) : CGPoint(x: start.x, y: end.y)
        let last = isKnight ? bend : start
        let dx = end.x - last.x, dy = end.y - last.y
        let distance = max(1, hypot(dx, dy))
        let ux = dx / distance, uy = dy / distance
        let headBase = CGPoint(x: end.x - ux * tile * 0.27, y: end.y - uy * tile * 0.27)
        let wing = tile * 0.16
        let line = Path { path in
            path.move(to: start)
            if isKnight { path.addLine(to: bend) }
            path.addLine(to: headBase)
        }
        let head = Path { path in
            path.move(to: end)
            path.addLine(to: CGPoint(x: headBase.x - uy * wing, y: headBase.y + ux * wing))
            path.addLine(to: CGPoint(x: headBase.x + uy * wing, y: headBase.y - ux * wing))
            path.closeSubpath()
        }
        ZStack {
            line.stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: tile * 0.13, lineCap: .round, lineJoin: .round))
            line.stroke(Theme.accent.opacity(0.88), style: StrokeStyle(lineWidth: tile * 0.09, lineCap: .round, lineJoin: .round))
            head.fill(Theme.accent.opacity(0.95))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Best move \(move.uci)")
    }

    private func point(for square: Int, tile: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(square % 8) + 0.5) * tile,
                y: (CGFloat(7 - square / 8) + 0.5) * tile)
    }
}

private struct LibraryView: View {
    @EnvironmentObject var model: GameModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your games").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Stored only on this Mac. Open any game to review or continue.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { model.newGame() } label: { Label("New game", systemImage: "plus") }.buttonStyle(AccentButton())
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.data.games.sorted(by: { $0.updatedAt > $1.updatedAt })) { game in
                        Button { model.open(game.id) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "checkerboard.rectangle").font(.system(size: 21)).foregroundStyle(Theme.accent)
                                    .frame(width: 42, height: 42).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(game.title).font(.system(size: 15, weight: .semibold))
                                    Text(game.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text("\(game.moves.count) ply").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                Text(game.result ?? "Resume").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                                    .frame(width: 70, alignment: .trailing)
                                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                            }
                            .padding(16)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(28)
    }
}

private struct SettingsView: View {
    @EnvironmentObject var model: GameModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Make this studio yours.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("OPPONENT")
                    HStack {
                        Text("Stockfish strength").font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text("\(model.data.opponentElo) Elo").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Theme.accent)
                    }
                    Slider(value: Binding(get: { Double(model.data.opponentElo) }, set: { model.data.opponentElo = Int($0 / 10) * 10; model.persist() }), in: 1320...3190, step: 10)
                        .tint(Theme.accent)
                    HStack { Text("1320"); Spacer(); Text("3190") }.font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Text("The selected strength applies to new games. Stockfish's Elo setting is an engine calibration, so it is not directly comparable with your local rating.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Divider().overlay(Theme.border)
                    pathRow(label: "Stockfish executable", value: model.data.enginePath) { chooseExecutable { model.data.enginePath = $0; model.persist() } }
                    Text(model.hasEngine ? "Stockfish is ready." : "Install Stockfish (for example, `brew install stockfish`), then choose its executable.")
                        .font(.system(size: 12)).foregroundStyle(model.hasEngine ? Theme.accent : .orange)
                }
                .cardStyle()
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("CODEX COACH")
                    Toggle("Enable Codex coach", isOn: Binding(get: { model.data.coachEnabled }, set: {
                        model.data.coachEnabled = $0
                        model.persist()
                        if $0 { model.startPostGameAnalysisIfNeeded() }
                    }))
                        .toggleStyle(.switch).font(.system(size: 14))
                    Text("Uses your local Codex CLI sign-in. Completed games get an automatic review; questions send the current FEN, move list, and available engine analysis to Codex.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    pathRow(label: "Codex executable", value: model.data.codexPath) { chooseExecutable { model.data.codexPath = $0; model.persist() } }
                    Text(FileManager.default.isExecutableFile(atPath: model.data.codexPath) ? "Codex CLI found." : "Choose an installed Codex CLI executable.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .cardStyle()
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("LOCAL DATA")
                    Text("\(model.data.games.count) saved games · current rating \(model.data.rating)")
                        .font(.system(size: 13))
                    Text(GameStorage.url.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted).textSelection(.enabled)
                }
                .cardStyle()
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(Theme.muted)
    }

    private func pathRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 13, weight: .medium))
                Text(value.isEmpty ? "Not selected" : value).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Button("Choose…", action: action).buttonStyle(SubtleButton())
        }
    }

    private func chooseExecutable(_ update: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { update(url.path) }
    }
}

private struct AccentButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.background)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SubtleButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Theme.background.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
    }
}

private extension View {
    func cardStyle() -> some View { modifier(CardModifier()) }
}
