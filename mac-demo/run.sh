#!/bin/zsh
# Launch the Tomodachi demo with AI keys from the repo's .env (never committed).
# Keys are passed to the app's environment only; nothing is written to disk or the Keychain.
cd "${0:A:h}"
app="build/Build/Products/Debug/Tomodachi.app"
[[ -d "$app" ]] || { echo "Build first: see README.md"; exit 1; }

envargs=()
if [[ -f ../.env ]]; then
  set -a; source ../.env; set +a
  for name in OPENAI_API_KEY ANTHROPIC_API_KEY; do
    [[ -n "${(P)name}" ]] && envargs+=(--env "$name=${(P)name}")
  done
fi

pkill -f "Tomodachi.app/Contents/MacOS/Tomodachi" 2>/dev/null && sleep 0.5
open "${envargs[@]}" "$app"
