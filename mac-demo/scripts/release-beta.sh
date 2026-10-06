#!/usr/bin/env bash
# Build a signed, notarized Tomodachi beta that testers can open without warnings.
#
#   mac-demo/scripts/release-beta.sh                 archive, sign (Developer ID), notarize, staple, zip
#   mac-demo/scripts/release-beta.sh --no-notarize   archive and sign only (quick local check)
#   mac-demo/scripts/release-beta.sh --owner         archive and sign the owner's copy: mac-demo/build/owner
#                                                     (run.sh opens it; it syncs with the iPhone through iCloud)
#
# Xcode signs automatically (team in NotchBuddy/project.yml): the export makes the Developer ID profile with
# iCloud and push notifications (TomoSync), so Xcode must be signed in to that team.
#
# One-time setup for notarizing (you type an app-specific password from appleid.apple.com; it's stored in your
# Keychain):
#   xcrun notarytool store-credentials tomodachi-notary --apple-id "you@example.com" --team-id <the same team>
#
# The version comes from CFBundleShortVersionString in NotchBuddy/project.yml.
set -euo pipefail

MODE="${1:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"          # mac-demo/
PROJ="$ROOT/NotchBuddy"
OUT="$ROOT/build/release"
[ "$MODE" = "--owner" ] && OUT="$ROOT/build/owner"
ARCHIVE="$ROOT/build/release-derived/Tomodachi.xcarchive"
die() { echo "error: $*" >&2; exit 1; }

TEAM=$(sed -nE 's/^ *DEVELOPMENT_TEAM: *([A-Z0-9]{10}).*/\1/p' "$PROJ/project.yml" | head -1)
[ -n "$TEAM" ] || die "no DEVELOPMENT_TEAM in project.yml"
PROFILE="tomodachi-notary"

VERSION=$(sed -nE 's/^ *CFBundleShortVersionString: *"([^"]+)".*/\1/p' "$PROJ/project.yml" | head -1)
[ -n "$VERSION" ] || die "no CFBundleShortVersionString in project.yml"

security find-identity -v -p codesigning | grep "Developer ID Application" | grep -q "($TEAM)" \
  || die "no 'Developer ID Application' certificate for team $TEAM (Xcode → Settings → Accounts)"

if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
  echo "warning: uncommitted changes. This build won't match a commit."
fi

echo "Building Tomodachi $VERSION (Release)…"
cd "$PROJ"
xcodegen generate >/dev/null
rm -rf "$OUT" "$ARCHIVE" && mkdir -p "$OUT"
xcodebuild -quiet archive -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$ROOT/build/release-derived" -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates
xcodebuild -quiet -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" \
  -exportPath "$OUT" -allowProvisioningUpdates

APP="$OUT/Tomodachi.app"
ZIP="$OUT/Tomodachi-$VERSION-beta.zip"

echo "Checking the signature…"
codesign --verify --deep --strict "$APP" || die "signature check failed"
# Capture first: `cmd | grep -q` fails under pipefail when grep exits early.
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)
[[ "$SIGNATURE" == *"runtime"* ]] || die "hardened runtime is off"
[[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]] || die "not signed with Developer ID"
[[ "$SIGNATURE" == *"TeamIdentifier=$TEAM"* ]] || die "not signed by team $TEAM"
[[ "$ENTITLEMENTS" == *"device.audio-input"* ]] || die "microphone entitlement missing"
[[ "$ENTITLEMENTS" == *"iCloud.com.zenbujapanese.tomodachi"* ]] || die "iCloud entitlement missing"
[[ "$ENTITLEMENTS" == *"<string>Production</string>"* ]] || die "not on CloudKit's Production environment"
[[ "$ENTITLEMENTS" == *"<string>production</string>"* ]] || die "push notifications aren't production"
[ ! -d "$APP/Contents/Resources/sounds" ] || die "Coucou's sounds are bundled; they can't be distributed"

if [ "$MODE" = "--owner" ]; then
  echo "The owner's copy is ready: $APP (mac-demo/run.sh opens it)"
  exit 0
fi

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
