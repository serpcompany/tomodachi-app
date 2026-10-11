#!/usr/bin/env bash
# The finish gate's one command (SERP's verification-cadence.md): the Mac build, TomoCore's tests, the self-test and
# both repo checks, in that order, stopping at the first failure with a non-zero exit. Run it once per state, when the
# branch is done, from any directory. It never touches the owner's Tomo or screen: the self-test runs headless
# (TOMO_HEADLESS=1) on a temporary data folder, deleted afterwards. The evidence a change needs on top (snapshots,
# the iPhone build and UI journeys, which macOS CI runs) is in docs/verification.md.
#
#   scripts/finish-gate.sh
#   XCODEBUILD_FLAGS="CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS=" \
#     scripts/finish-gate.sh    # only if automatic signing fails on this Mac
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
logs="$(mktemp -d "${TMPDIR:-/tmp}/tomo-finish-gate.XXXXXX")"
data="$(mktemp -d "${TMPDIR:-/tmp}/tomo-finish-gate-data.XXXXXX")"
trap 'rm -rf "$data"' EXIT
start=$SECONDS

# Runs a step quietly into its own log; on failure, prints the failing lines (a self-test FAIL, a compiler error, a
# failed test) and the log's end, and stops with the step's exit code.
step() {
  local name="$1"; shift
  local log="$logs/$name.log" began=$SECONDS
  printf '%-26s' "$name"
  if "$@" >"$log" 2>&1; then
    printf 'ok    %4ss\n' "$((SECONDS - began))"
  else
    local code=$?
    printf 'FAIL  %4ss  (%s)\n' "$((SECONDS - began))" "$log"
    grep -nE -A6 '^FAIL |error:|failed|Failed' "$log" | head -n 80 || true
    echo "…"
    tail -n 15 "$log"
    echo "finish gate: failed at '$name' after $((SECONDS - start)) s"
    exit "$code"
  fi
}

# Each step chains with && : `set -e` doesn't apply inside a function called from `if`.
# xcodegen must leave the committed project as it is, or the gate would pass on a tree that matches no commit.
mac_build() {
  # shellcheck disable=SC2086  # XCODEBUILD_FLAGS is a list of build settings
  cd "$root/mac-demo/NotchBuddy" && xcodegen && project_unchanged && xcodebuild -scheme NotchBuddy \
    -configuration Debug -derivedDataPath ../build -allowProvisioningUpdates ${XCODEBUILD_FLAGS:-} build
}

project_unchanged() {
  git -C "$root" diff --quiet -- mac-demo/NotchBuddy/NotchBuddy.xcodeproj || {
    echo "error: xcodegen changed mac-demo/NotchBuddy/NotchBuddy.xcodeproj; commit the regenerated project first"
    git -C "$root" diff --stat -- mac-demo/NotchBuddy/NotchBuddy.xcodeproj
    false
  }
}

swift_test() {
  cd "$root/TomoCore" && swift test
}

self_test() {
  TOMO_HEADLESS=1 TOMO_SELFTEST=1 TOMO_DATA_DIR="$data" \
    "$root/mac-demo/build/Build/Products/Debug/Tomodachi.app/Contents/MacOS/Tomodachi"
}

# CI builds with the Xcode pinned in .xcode-version; a different one here is reported, not fatal
# (docs/verification.md: say so in the PR, and CI's compile is the one that counts).
pinned="$(tr -d '[:space:]' < "$root/.xcode-version")"
xcode="$(xcodebuild -version | awk 'NR==1 {print $2}')"
[ "$xcode" = "$pinned" ] || echo "note: building with Xcode $xcode, not the pinned $pinned; CI's compile is the one that counts"

step "Mac build" mac_build
step "TomoCore tests" swift_test
step "Self-test" self_test
step "Docs check" node "$root/.github/scripts/check-docs.mjs"
step "Swift text check" node "$root/.github/scripts/check-swift-text.mjs"

checks=$(grep -c '^ok ' "$logs/Self-test.log" || true)
echo "finish gate: passed in $((SECONDS - start)) s (self-test: $checks checks; logs in $logs)"
