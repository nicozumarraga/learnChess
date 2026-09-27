#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" Sources/LearnChess/Chess.swift Sources/LearnChess/Services.swift scripts/main.swift -o .build/learnchess-check
.build/learnchess-check
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library Sources/LearnChess/Chess.swift Sources/LearnChess/Services.swift Sources/LearnChess/GameModel.swift scripts/ModelCheck.swift -o .build/learnchess-model-check
.build/learnchess-model-check
