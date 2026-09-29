# LearnChess

A local macOS chess studio built with SwiftUI. Play as White against Stockfish, review positions and past games, and optionally ask the Codex CLI for coaching.

The app icon source is [`Assets/AppIcon.png`](Assets/AppIcon.png); `scripts/build-app.sh` converts it into the macOS icon used by the app bundle.

## Features

- Legal chess moves, checkmate and stalemate detection, SAN move list, board navigation, and saved games that reopen at the last move.
- Stockfish play with a selectable 1320–3190 engine Elo setting, plus full strength analysis, best move, score, and win/draw/loss estimate.
- Best move arrows on the board, including an L-shaped arrow for knight moves.
- Optional live help prepares a comparison after you move. Select **Review last move** to reveal the earlier position and arrow in a small review board; the main board stays playable. **Show hint** reveals the current best move before you play. Games without live help keep hints and coaching unavailable until completion.
- A local rating updated after every completed game, including games with live help. This is a personal progress indicator, not an official Elo rating. Previously completed assisted games are counted once when upgrading.
- A collapsible sidebar and compact Focus view with a large board, recent moves, and a small status panel.
- Completed games receive full-strength Stockfish move labels, including good, inaccuracy, mistake, and blunder. Brilliant and great are cautious heuristics, not official chess.com classifications. With Codex enabled, the app also writes an automatic game review. Move references in Codex answers are clickable and replay the board position before and after the cited move.
- From any blunder in a completed game, select **Try line** to see Stockfish's preferred move and play a short practice continuation against full-strength Stockfish. Both the large board and the small review board accept moves. For a Black blunder, Stockfish's better move is played first so you continue as White. Practice is temporary and leaves the saved game and rating untouched.
- Optional Codex coach with four question shortcuts and a custom question. Replies render simple Markdown, and each game's conversation is saved locally across app restarts. Recent turns are included in follow-up prompts, so the coach can answer questions about earlier replies. The app sends the current FEN, moves, conversation, and available engine results as text using `codex exec --ephemeral --sandbox read-only`.

Games and settings are stored in `~/Library/Application Support/LearnChess/games.json`. The app does not upload games itself. Enabling the Codex coach sends the question and board context through the installed Codex CLI.

## Run

Requires macOS 13+, the Swift toolchain, and Stockfish. With Homebrew:

```sh
brew install stockfish
swift run
```

To build a Finder-launchable application:

```sh
zsh scripts/build-app.sh
open build/LearnChess.app
```

If Stockfish is installed elsewhere, choose its executable in Settings. For the coach, install and sign in to Codex CLI, then enable it in Settings. No API key is required when using an existing CLI sign-in.

## Development

```sh
zsh scripts/check.sh
```

The app uses a native SwiftUI board and JSON persistence. Stockfish is a separate local UCI process and is not bundled with the app.
