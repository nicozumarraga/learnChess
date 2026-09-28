#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build
sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
sdk="$(realpath "$sdk")"
if [[ "$sdk" == */MacOSX27*.sdk && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swiftc -sdk "$sdk" -module-cache-path "$PWD/.build/module-cache" Sources/LearnChess/Chess.swift Sources/LearnChess/Services.swift scripts/main.swift -o .build/learnchess-check
.build/learnchess-check
swiftc -sdk "$sdk" -module-cache-path "$PWD/.build/module-cache" -parse-as-library Sources/LearnChess/Chess.swift Sources/LearnChess/Services.swift Sources/LearnChess/GameModel.swift Sources/LearnChess/MoveLinks.swift scripts/ModelCheck.swift -o .build/learnchess-model-check
.build/learnchess-model-check
