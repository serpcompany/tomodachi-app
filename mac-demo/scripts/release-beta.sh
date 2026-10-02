#!/usr/bin/env bash
# Build a signed, notarized Tomodachi beta that testers can open without warnings.
#
#   mac-demo/scripts/release-beta.sh                 build, sign, notarize, staple, zip
#   mac-demo/scripts/release-beta.sh --no-notarize   build and sign only (quick local check)
#
# One-time setup (you type an app-specific password from appleid.apple.com; it's stored in your Keychain):
#   xcrun notarytool store-credentials tomodachi-notary --apple-id "you@example.com" --team-id <the same team>
#
# The version comes from CFBundleShortVersionString in NotchBuddy/project.yml.
set -euo pipefail

MODE="${1:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"          # mac-demo/
PROJ="$ROOT/NotchBuddy"
OUT="$ROOT/build/release"
die() { echo "error: $*" >&2; exit 1; }

# Team: DEVELOPMENT_TEAM in NotchBuddy/project.yml (or TOMO_TEAM=XXXXXXXXXX to override)
TEAM="${TOMO_TEAM:-$(sed -nE 's/^ *DEVELOPMENT_TEAM: *([A-Z0-9]{10}).*/\1/p' "$PROJ/project.yml" | head -1)}"
[ -n "$TEAM" ] || die "no DEVELOPMENT_TEAM in project.yml"
PROFILE="tomodachi-notary"

VERSION=$(sed -nE 's/^ *CFBundleShortVersionString: *"([^"]+)".*/\1/p' "$PROJ/project.yml" | head -1)
[ -n "$VERSION" ] || die "no CFBundleShortVersionString in project.yml"

# Several copies of the certificate are installed, so sign with an exact SHA-1, not the name.
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM)" | head -1 | awk '{print $2}' || true)
[ -n "$IDENTITY" ] || die "no 'Developer ID Application' certificate for team $TEAM (Xcode → Settings → Accounts)"

if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
  echo "warning: uncommitted changes. This beta won't match a commit."
fi

echo "Building Tomodachi $VERSION (Release)…"
cd "$PROJ"
xcodegen generate >/dev/null
rm -rf "$OUT" && mkdir -p "$OUT"
xcodebuild -quiet -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$ROOT/build/release-derived" build \
  CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" CONFIGURATION_BUILD_DIR="$OUT"

APP="$OUT/Tomodachi.app"
ZIP="$OUT/Tomodachi-$VERSION-beta.zip"

echo "Checking the signature…"
codesign --verify --deep --strict "$APP" || die "signature check failed"
# Capture first: `cmd | grep -q` fails under pipefail when grep exits early.
SIGNATURE=$(codesign -dv "$APP" 2>&1)
ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)
[[ "$SIGNATURE" == *"runtime"* ]] || die "hardened runtime is off"
[[ "$SIGNATURE" == *"TeamIdentifier=$TEAM"* ]] || die "not signed by team $TEAM"
[[ "$ENTITLEMENTS" == *"device.audio-input"* ]] || die "microphone entitlement missing"
[ ! -d "$APP/Contents/Resources/sounds" ] || die "Coucou's sounds are bundled; they can't be distributed"

ditto -c -k --keepParent "$APP" "$ZIP"
if [ "$MODE" = "--no-notarize" ]; then
  echo "Signed, not notarized: $ZIP"
  exit 0
fi

echo "Sending to Apple for notarization (usually a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait \
  || die "notarization failed. Details: xcrun notarytool log <id> --keychain-profile $PROFILE"
xcrun stapler staple "$APP"
spctl -a -vv "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Beta ready for testers: $ZIP"
