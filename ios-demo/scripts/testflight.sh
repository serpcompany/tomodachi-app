#!/bin/zsh
# Archives the iPhone app and uploads it to App Store Connect for TestFlight.
# Needs: Xcode signed in to the Zenbu Japanese team (Xcode → Settings → Accounts), and the app record
# "Tomodachi" (bundle ID com.zenbujapanese.tomodachi) in App Store Connect. Xcode picks the next build number.
set -euo pipefail
# Xcode packages the upload with /usr/bin/rsync, which starts a second rsync from PATH; Homebrew's rsync 3.x
# rejects Apple's options ("Copy failed"). Apple's tools first.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
cd "${0:A:h}/../Tomodachi"
xcodegen -q
archive=../build/Tomodachi.xcarchive
rm -rf "$archive"
xcodebuild archive -scheme Tomodachi -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" -derivedDataPath ../build -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist ../scripts/ExportOptions.plist \
  -exportPath ../build/export -allowProvisioningUpdates
echo "Uploaded. It shows in App Store Connect → TestFlight once Apple has processed it (usually 5–15 min)."
