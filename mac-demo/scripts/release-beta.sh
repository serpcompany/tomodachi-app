#!/usr/bin/env bash
# Build a signed, notarized Tomodachi beta that testers can open without warnings.
#
#   mac-demo/scripts/release-beta.sh                 archive, sign (Developer ID), notarize, staple, zip
#   mac-demo/scripts/release-beta.sh --no-notarize   archive and sign only (quick local check)
#   mac-demo/scripts/release-beta.sh --owner         archive and sign the owner's copy: mac-demo/build/owner
#                                                     (run.sh opens it; it syncs with the iPhone through iCloud)
#
# Xcode signs automatically (team in NotchBuddy/project.yml): the export makes the Developer ID profile with
# iCloud and push notifications (TomoSync), so Xcode must be signed in to that team. Notarizing goes through the
# same Xcode account (like Organizer's "Distribute App"), so there's no notary password to set up.
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

check_app() {
  codesign --verify --deep --strict "$1" || die "signature check failed"
  # Capture first: `cmd | grep -q` fails under pipefail when grep exits early.
  local signature entitlements
  signature=$(codesign -dvv "$1" 2>&1)
  entitlements=$(codesign -d --entitlements - --xml "$1" 2>/dev/null)
  [[ "$signature" == *"runtime"* ]] || die "hardened runtime is off"
  [[ "$signature" == *"Authority=Developer ID Application"* ]] || die "not signed with Developer ID"
  [[ "$signature" == *"TeamIdentifier=$TEAM"* ]] || die "not signed by team $TEAM"
  [[ "$entitlements" == *"iCloud.com.zenbujapanese.tomo"* ]] || die "iCloud entitlement missing"
  [[ "$entitlements" == *"<string>Production</string>"* ]] || die "not on CloudKit's Production environment"
  [[ "$entitlements" == *"<string>production</string>"* ]] || die "push notifications aren't production"
  [ ! -d "$1/Contents/Resources/sounds" ] || die "Coucou's sounds are bundled; they can't be distributed"
}

echo "Checking the signature…"
check_app "$APP"

if [ "$MODE" = "--owner" ]; then
  echo "The owner's copy is ready: $APP (mac-demo/run.sh opens it)"
  exit 0
fi

if [ "$MODE" = "--no-notarize" ]; then
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Signed, not notarized: $ZIP"
  exit 0
fi

# Upload the archive to Apple's notary service with Xcode's account (the same export options, sent instead of
# saved), then fetch the notarized, stapled app once Apple has finished.
echo "Sending to Apple for notarization (usually a few minutes)…"
UPLOAD="$ROOT/build/release-upload"
NOTARIZED="$ROOT/build/release-notarized"
rm -rf "$UPLOAD" && mkdir -p "$UPLOAD"
plutil -replace destination -string upload -o "$UPLOAD/ExportOptions.plist" "$ROOT/scripts/ExportOptions.plist"
xcodebuild -quiet -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$UPLOAD/ExportOptions.plist" \
  -exportPath "$UPLOAD" -allowProvisioningUpdates
for _ in $(seq 60); do                            # up to 30 minutes
  rm -rf "$NOTARIZED"
  if LOG=$(xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$NOTARIZED" 2>&1); then break; fi
  [[ "$LOG" == *"is processing"* ]] || die "notarization failed: $(tail -3 <<<"$LOG")"
  sleep 30
done
[ -d "$NOTARIZED/Tomodachi.app" ] || die "Apple hasn't finished after 30 minutes. Fetch it later with:
  xcodebuild -exportNotarizedApp -archivePath \"$ARCHIVE\" -exportPath \"$NOTARIZED\""

rm -rf "$APP" && ditto "$NOTARIZED/Tomodachi.app" "$APP"
check_app "$APP"
xcrun stapler validate "$APP"
spctl -a -vv "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
echo "Beta ready for testers: $ZIP"
