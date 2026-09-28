#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
sdk="$(realpath "$sdk")"
if [[ "$sdk" == */MacOSX27*.sdk && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SDKROOT="$sdk"
swift build --disable-sandbox -c release --scratch-path .build -debug-info-format none -Xswiftc -sdk -Xswiftc "$sdk"
app="build/LearnChess.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/AppIcon.iconset
cp .build/release/LearnChess "$app/Contents/MacOS/LearnChess"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Assets/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Assets/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 scripts/make_icns.py build/AppIcon.iconset "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.nicozumarraga.LearnChess</string>
<key>CFBundleName</key><string>LearnChess</string>
<key>CFBundleDisplayName</key><string>LearnChess</string>
<key>CFBundleExecutable</key><string>LearnChess</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
touch "$app"
echo "$PWD/$app"
