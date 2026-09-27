# LearnChess

A local macOS chess studio built with SwiftUI. Play as White against Stockfish, review positions and past games, and optionally ask the Codex CLI for coaching.

The app icon source is [`Assets/AppIcon.png`](Assets/AppIcon.png); `scripts/build-app.sh` converts it into the macOS icon used by the app bundle.

## Features

- Legal chess moves, checkmate and stalemate detection, SAN move list, board navigation, and saved games that reopen at the last move.
- Stockfish play with a selectable 1320–3190 engine Elo setting, plus full strength analysis, best move, score, and win/draw/loss estimate.
- Best move arrows on the board, including an L-shaped arrow for knight moves.
- Optional live help and per-move comparison stored with assisted games. Assisted games do not change the local rating.
- A local rating updated after completed, unassisted games. This is a personal progress indicator, not an official Elo rating.
- A collapsible sidebar and compact Focus view with a large board, recent moves, and a small status panel.
- Optional Codex coach with four question shortcuts and a custom question. The app sends the current FEN, moves, and available engine results as text using `codex exec --ephemeral --sandbox read-only`.

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
