#!/bin/zsh
# Tomodachi's iPhone simulators: one per agent, named `tomodachi--<scope>` and addressed by UDID (SERP's
# simulators standard: docs/engineering/technology/simulators.md in serpcompany/serp).
#
#   ios-demo/scripts/simulator.sh udid [scope]     find or create tomodachi--<scope>; prints its UDID and nothing else
#   ios-demo/scripts/simulator.sh delete [scope]   shut down and delete tomodachi--<scope>
#   ios-demo/scripts/simulator.sh prune [-n]       delete each tomodachi--<scope> whose worktree and branch are gone,
#                                                  unless it's booted (someone may be using it); -n only lists them.
#                                                  A scope starting with a worktree's or branch's name and a hyphen
#                                                  (`std-6-shots`) is kept while that worktree or branch exists.
#   ios-demo/scripts/simulator.sh scope            print the default scope
#
# The scope defaults to this worktree's folder name, or the branch's name in the main checkout. A new simulator is
# the newest iPhone Pro the newest installed iOS runtime supports (TOMO_SIM_DEVICE="iPhone 17 Pro Max" picks
# another model). The per-app `tomodachi` simulator is the owner's and long-lived: this script never deletes it.
# Pass the UDID to every simctl and xcodebuild command (-destination "platform=iOS Simulator,id=$udid"); never
# open Simulator.app, since simctl runs headless.
set -euo pipefail
app=tomodachi
repo="${0:A:h}/../.."

die() { print -u2 -- "simulator.sh: $*"; exit 1; }

# Letters, digits, dots, hyphens and underscores only, as a simulator name keeps them.
clean() { print -r -- "${1//[^A-Za-z0-9._-]/-}"; }

default_scope() {
  local top gitdir common
  top=$(git -C "$repo" rev-parse --show-toplevel)
  gitdir=$(git -C "$repo" rev-parse --absolute-git-dir)
  common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
  if [[ "$gitdir" != "$common" ]]; then clean "${top:t}"          # a worktree: its folder's name
  else clean "$(git -C "$repo" branch --show-current)"; fi          # the main checkout: the branch
}

scope_of() {
  local s
  s=$(clean "${1:-$(default_scope)}")
  [[ -n "$s" ]] || die "no scope (a detached HEAD in the main checkout?): pass one"
  print -r -- "$s"
}

# The simulators whose name is $1, or (with a trailing *) starts with it, as "UDID STATE NAME" lines.
devices() {
  xcrun simctl list devices -j | python3 -I -c '
import json, sys
want = sys.argv[1]
for runtime, found in json.load(sys.stdin)["devices"].items():
    for d in found:
        if d.get("isAvailable", True) and (d["name"] == want or (want.endswith("*") and d["name"].startswith(want[:-1]))):
            print(d["udid"], d["state"], d["name"])' "$1"
}

# "DEVICE-TYPE-ID RUNTIME-ID": the newest iOS runtime installed, and the iPhone Pro (or TOMO_SIM_DEVICE) it runs.
newest() {
  local types runtimes
  types=$(xcrun simctl list devicetypes -j)
  runtimes=$(xcrun simctl list runtimes -j)
  python3 -I -c '
import json, re, sys
types = {t["identifier"]: t["name"] for t in json.loads(sys.argv[1])["devicetypes"]}
ios = [r for r in json.loads(sys.argv[2])["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
if not ios: sys.exit("no iOS runtime installed (Xcode → Settings → Components)")
runtime = max(ios, key=lambda r: [int(x) for x in r["version"].split(".")])
supported = [t["identifier"] for t in runtime.get("supportedDeviceTypes", [])] or list(types)
want = sys.argv[3]
if want:
    picks = [i for i in supported if types.get(i) == want]
else:
    pro = [(int(m.group(1)), i) for i in supported if (m := re.fullmatch(r"iPhone (\d+) Pro", types.get(i, "")))]
    picks = [max(pro)[1]] if pro else []
if not picks: sys.exit("no " + (want or "iPhone Pro") + " for iOS " + runtime["version"])
print(picks[0], runtime["identifier"])' "$types" "$runtimes" "${TOMO_SIM_DEVICE:-}"
}

cmd_udid() {
  local name="$app--$(scope_of "${1:-}")" found
  found=("${(@f)$(devices "$name")}")
  if [[ -n "${found[1]}" ]]; then
    (( ${#found} == 1 )) || print -u2 -- "simulator.sh: ${#found} simulators are named $name; using the first"
    print -r -- "${found[1]%% *}"
    return
  fi
  local pick type runtime
  pick=$(newest) || die "can't pick a device type and runtime"
  type="${pick%% *}" runtime="${pick##* }"
  print -u2 -- "simulator.sh: creating $name (${type##*.}, ${runtime##*.})"
  xcrun simctl create "$name" "$type" "$runtime"
}

cmd_delete() {
  local name="$app--$(scope_of "${1:-}")" line udid
  local -a found
  found=("${(@f)$(devices "$name")}")
  [[ -n "${found[1]}" ]] || { print -u2 -- "simulator.sh: no simulator named $name"; return; }
  for line in "${found[@]}"; do
    udid="${line%% *}"
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    xcrun simctl delete "$udid"
    print -u2 -- "simulator.sh: deleted $name ($udid)"
  done
}

# A scope is still in use while a worktree with that folder name, or a branch with that name, exists; a scope that
# starts with one of them and a hyphen (`std-6-shots`) lives as long as it.
in_use() {
  local scope="$1" key wt branch live
  matches() { [[ "$scope" == "$1" || "$scope" == "$1-"* ]]; }
  git -C "$repo" worktree list --porcelain | while read -r key wt; do
    [[ "$key" == worktree ]] && matches "$(clean "${wt:t}")" && return 0
  done
  git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads | while read -r branch; do
    matches "$(clean "$branch")" && return 0
  done
  return 1
}

cmd_prune() {
  local dry="${1:-}" line udid state name scope
  devices "$app--*" | while read -r udid state name; do
    scope="${name#$app--}"
    if in_use "$scope"; then print -u2 -- "simulator.sh: keeping $name (its worktree or branch exists)"
    elif [[ "$state" != Shutdown ]]; then print -u2 -- "simulator.sh: keeping $name ($state, maybe in use)"
    elif [[ "$dry" == -n ]]; then print -u2 -- "simulator.sh: would delete $name ($udid)"
    else xcrun simctl delete "$udid" && print -u2 -- "simulator.sh: deleted $name ($udid)"; fi
  done
}

case "${1:-}" in
  udid) cmd_udid "${2:-}" ;;
  delete) cmd_delete "${2:-}" ;;
  prune) cmd_prune "${2:-}" ;;
  scope) scope_of "" ;;
  *) die "usage: simulator.sh udid [scope] | delete [scope] | prune [-n] | scope" ;;
esac
