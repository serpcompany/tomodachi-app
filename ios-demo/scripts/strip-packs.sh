#!/bin/sh
# Leaves the language packs the iPhone app can't reach out of a built bundle (#92). TomoCore copies every pack in
# Resources/languages into its resource bundle, for the Mac too; the iPhone has no way to pick another language to
# learn, so the Spanish draft would only be dead weight for App Review to find.
# Runs as the last build phase of the app and of the widget extension, before Xcode signs each bundle.
# Usage: strip-packs.sh <the .app or .appex folder>
set -eu
packs="$1/TomoCore_TomoCore.bundle/languages"
if [ ! -d "$packs" ]; then
  echo "warning: no TomoCore language packs in $1"
  exit 0
fi
rm -f "$packs/es.json"
