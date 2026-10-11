#!/bin/zsh
# Archives the iPhone app and uploads it to App Store Connect for TestFlight.
# Needs: Xcode signed in to the Zenbu Japanese team (Xcode → Settings → Accounts) for signing, and the app record
# "Tomodachi by Zenbu Japanese" (bundle ID com.zenbujapanese.tomo) in App Store Connect.
# The upload uses an App Store Connect API key when the repo's .env names one (ASC_KEY_ID, ASC_ISSUER_ID), with the
# key file at ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 (never in the repo): Xcode signs and exports
# locally, and altool uploads with the key. Without a key, Xcode's own account uploads (scripts/ExportOptions.plist).
# Each build is numbered by its date and time (YYMMDD.HHMM), so every upload counts up.
set -euo pipefail
# Xcode packages the upload with /usr/bin/rsync, which starts a second rsync from PATH; Homebrew's rsync 3.x
# rejects Apple's options ("Copy failed"). Apple's tools first.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
root="${0:A:h}/../.."
if [[ -f "$root/.env" ]]; then set -a; source "$root/.env"; set +a; fi
cd "${0:A:h}/../Tomodachi"
xcodegen -q
build=$(date +%y%m%d.%H%M)
archive=../build/Tomodachi.xcarchive
rm -rf "$archive" ../build/export
xcodebuild archive -scheme Tomodachi -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" -derivedDataPath ../build -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$build"
# Only the product's identity goes to TestFlight (SERP's native-app-build-identity standard): the app is
# com.zenbujapanese.tomo and its widgets com.zenbujapanese.tomo.widgets, never a Debug or test build's.
check_identity() {
  local app="$1/Products/Applications/Tomodachi.app" id widgets
  id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist" 2>/dev/null || true)
  [[ "$id" == "com.zenbujapanese.tomo" ]] || { echo "error: the archived app's bundle ID is '$id', not com.zenbujapanese.tomo" >&2; exit 1; }
  widgets=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/PlugIns/TomoWidgets.appex/Info.plist" 2>/dev/null || true)
  [[ "$widgets" == "com.zenbujapanese.tomo.widgets" ]] || { echo "error: the widgets' bundle ID is '$widgets', not com.zenbujapanese.tomo.widgets" >&2; exit 1; }
}
check_identity "$archive"
key="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-none}.p8"
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -f "$key" ]]; then
  local_options="$(mktemp -d)/ExportOptions.plist"
  sed 's#<string>upload</string>#<string>export</string>#' ../scripts/ExportOptions.plist > "$local_options"
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$local_options" \
    -exportPath ../build/export -allowProvisioningUpdates
  xcrun altool --upload-app -f ../build/export/Tomodachi.ipa -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
else
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist ../scripts/ExportOptions.plist \
    -exportPath ../build/export -allowProvisioningUpdates
fi
echo "Uploaded build $build. It shows in App Store Connect → TestFlight once Apple has processed it (usually 5–15 min)."
