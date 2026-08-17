#!/bin/bash
# Packages SteamHub.app into build/SteamHub.zip for sending to someone else.
#
# Free path (ad-hoc signed). The recipient has to approve it once in System Settings:
#
#   ./package.sh
#
# Paid path (Developer ID, $99/yr). The app just opens, no warning, no approval step.
# Needs a "Developer ID Application" certificate in your keychain and a notarytool
# profile stored once with:
#
#   xcrun notarytool store-credentials steamhub \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
# then:
#
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=steamhub ./package.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/SteamHub.app"
ZIP="build/SteamHub.zip"
SIGN_ID="${SIGN_ID:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

SIGN_ID="$SIGN_ID" ./build.sh

# ditto -c -k --keepParent is the only zip that reliably preserves the bundle's
# symlinks and signature; `zip -r` can corrupt the code signature.
#
# Unnotarized builds ship install.sh next to the app, because that script is what spares
# the recipient the Gatekeeper detour. Notarized builds don't need it — the app just
# opens — so those keep the plain, standard app-only zip that Apple's pipeline expects.
STAGE="build/stage"
rm -rf "$STAGE" && mkdir -p "$STAGE"

if [ -n "$NOTARY_PROFILE" ]; then
	ditto "$APP" "$STAGE/SteamHub.app"
else
	mkdir -p "$STAGE/SteamHub"
	ditto "$APP" "$STAGE/SteamHub/SteamHub.app"
	cp install.sh "$STAGE/SteamHub/install.sh"
	chmod +x "$STAGE/SteamHub/install.sh"
	cat > "$STAGE/SteamHub/INSTALL.txt" <<'TXT'
SteamHub — Steam achievement notifications for git pushes.

In Terminal, from this folder:

    ./install.sh

That installs to /Applications, launches it, and opens setup. Takes a second.

Prefer to do it by hand? Drag SteamHub.app to /Applications and open it — macOS will
block it once, and you clear that in System Settings > Privacy & Security > Open Anyway.
TXT
fi

PAYLOAD="$(find "$STAGE" -mindepth 1 -maxdepth 1)"
rm -f "$ZIP"
ditto -c -k --keepParent "$PAYLOAD" "$ZIP"
rm -rf "$STAGE"

if [ -n "$NOTARY_PROFILE" ]; then
	if [ "$SIGN_ID" = "-" ]; then
		echo "error: notarization needs a real Developer ID; set SIGN_ID too" >&2
		exit 1
	fi
	echo "Submitting to Apple for notarization (this takes a few minutes)…"
	xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

	# The ticket is stapled into the .app, so it must be re-zipped afterwards.
	# Stapling lets the recipient's Mac verify offline.
	xcrun stapler staple "$APP"
	rm -f "$ZIP"
	ditto -c -k --keepParent "$APP" "$ZIP"
	xcrun stapler validate "$APP"
	echo
	echo "Notarized. Send $ZIP — it will open with no warning."
else
	echo
	echo "Built $ZIP — send this one file. It contains SteamHub.app, install.sh"
	echo "and INSTALL.txt."
	echo
	echo "Tell them: unzip it, then in Terminal from that folder run"
	echo "  ./install.sh"
	echo
	echo "No Gatekeeper prompt. Quarantine only blocks double-clicking, not a script"
	echo "run from the shell, and install.sh clears it from the installed app."
fi

echo
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier|Authority" || true
ls -lh "$ZIP"
