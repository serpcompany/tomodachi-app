#!/bin/zsh
# Launch the owner's copy of Tomodachi with AI keys from the repo's .env (never committed).
# Keys are passed to the app's environment only; nothing is written to disk or the Keychain.
# The owner's copy is a Developer ID build (scripts/release-beta.sh --owner), so it syncs with the iPhone
# through iCloud; Debug builds use CloudKit's Development environment and are for test runs.
here="${0:A:h}"   # the absolute folder, taken before the cd: a relative $0 resolves differently after it
cd "$here"
app="build/owner/Tomodachi.app"
[[ -d "$app" ]] || { echo "Build the owner's copy first: scripts/release-beta.sh --owner"; exit 1; }

envargs=()
if [[ -f ../.env ]]; then
  set -a; source ../.env; set +a
  for name in OPENAI_API_KEY ANTHROPIC_API_KEY; do
    [[ -n "${(P)name}" ]] && envargs+=(--env "$name=${(P)name}")
  done
fi

# Quit only this copy, matched by its path from the start of the command line (SERP's native-app-build-identity
# standard): Debug builds and agents' test runs share the process name, and must keep running.
pkill -f "^$here/$app/Contents/MacOS/Tomodachi" 2>/dev/null && sleep 0.5
open "${envargs[@]}" "$app"
