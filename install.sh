#!/bin/bash
# Installs SteamHub.app and launches it. No Gatekeeper prompt, no Settings dance.
#
# The trick: macOS quarantines files that a *browser* or Slack/Mail downloads, not files
# fetched with curl. So downloading here and installing in one step skips the warning
# entirely. Anything already quarantined gets cleared explicitly below.
#
#   ./install.sh                        # install the SteamHub.app sitting next to this
#                                       # script, or ./build after ./build.sh
#   ./install.sh path/to/SteamHub.zip   # install from a zip someone sent you
#   ./install.sh https://…/SteamHub.zip # download and install
#
# Or, if the zip is hosted somewhere, a recipient needs exactly one line:
#
#   curl -fsSL https://…/install.sh | bash -s https://…/SteamHub.zip
set -euo pipefail

SOURCE="${1:-${STEAMHUB_URL:-}}"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

find_app() {
	case "$SOURCE" in
		http://*|https://*)
			echo "Downloading SteamHub…" >&2
			curl -fsSL "$SOURCE" -o "$TMP/SteamHub.zip"
			ditto -x -k "$TMP/SteamHub.zip" "$TMP/x"
			echo "$TMP/x/SteamHub.app"
			;;
		*.zip)
			ditto -x -k "$SOURCE" "$TMP/x"
			echo "$TMP/x/SteamHub.app"
			;;
		*.app)
			echo "$SOURCE"
			;;
		"")
			local here
			here="$(cd "$(dirname "$0")" && pwd)"
			# Shipped alongside the app inside the release zip.
			if [ -d "$here/SteamHub.app" ]; then
				echo "$here/SteamHub.app"
			# Otherwise fall back to whatever the local build produced.
			elif [ -d "$here/build/SteamHub.app" ]; then
				echo "$here/build/SteamHub.app"
			elif [ -f "$here/build/SteamHub.zip" ]; then
				ditto -x -k "$here/build/SteamHub.zip" "$TMP/x"
				echo "$TMP/x/SteamHub.app"
			else
				echo "error: nothing to install. Run ./build.sh first, or pass a zip/URL." >&2
				exit 1
			fi
			;;
		*)
			echo "error: expected a .zip, a .app, or an https:// URL — got '$SOURCE'" >&2
			exit 1
			;;
	esac
}

APP="$(find_app)"
[ -d "$APP" ] || { echo "error: SteamHub.app not found in $SOURCE" >&2; exit 1; }

# Quit a running copy so the replace doesn't race it.
pkill -x SteamHub 2>/dev/null || true

rm -rf "$DEST/SteamHub.app"
ditto "$APP" "$DEST/SteamHub.app"

# Clear quarantine in case the zip arrived by a route that set it (browser, Slack, Mail).
xattr -dr com.apple.quarantine "$DEST/SteamHub.app" 2>/dev/null || true

open "$DEST/SteamHub.app"

echo
echo "Installed to $DEST/SteamHub.app and launched."
echo "Look for the trophy in your menu bar. Setup opens automatically on first run."
