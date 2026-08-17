#!/bin/bash
# Builds SteamHub.app into ./build. Run ./build.sh, then open build/SteamHub.app.
#
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh
#
# signs for distribution instead of ad-hoc. See package.sh.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/SteamHub.app"
SIGN_ID="${SIGN_ID:--}"

# Universal, so the app also runs on Intel Macs.
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Info.plist "$APP/Contents/"
# Regenerate with ./make-icon.sh if chud.png changes.
[ -f AppIcon.icns ] && ditto --noextattr --norsrc AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto --noextattr --norsrc "$BIN_DIR/SteamHub" "$APP/Contents/MacOS/SteamHub"
ditto --noextattr --norsrc "$BIN_DIR/SteamHub_SteamHub.bundle" \
      "$APP/Contents/Resources/SteamHub_SteamHub.bundle"

# A stable signature (even ad-hoc) keeps the bundle identity fixed, so macOS remembers
# the Documents/Desktop access grants and the login-item registration across rebuilds.
#
# Ad-hoc can't carry a secure timestamp; a real Developer ID must, and must also enable
# the hardened runtime, or notarization rejects the upload.
if [ "$SIGN_ID" = "-" ]; then
	SIGN_FLAGS=(--timestamp=none)
else
	SIGN_FLAGS=(--timestamp --options runtime)
fi

# If this tree lives in an iCloud/Dropbox-synced folder, the sync daemon re-stamps
# com.apple.FinderInfo behind our back and codesign refuses to sign around it, so
# clear and retry rather than failing the build on a race.
signed=false
for _ in 1 2 3; do
	xattr -cr "$APP"
	if codesign --force "${SIGN_FLAGS[@]}" --sign "$SIGN_ID" "$APP" 2>/dev/null; then
		signed=true
		break
	fi
	sleep 1
done
$signed || { echo "error: could not codesign $APP with identity '$SIGN_ID'" >&2; exit 1; }

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/SteamHub"))"
