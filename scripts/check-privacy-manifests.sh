#!/usr/bin/env bash
# Fails when a built app, or a bundle with code inside it (an app extension, a framework), uses one of Apple's
# required-reason APIs that its own PrivacyInfo.xcprivacy doesn't declare (#234). App Store upload rejects such a build
# (ITMS-91053); this catches it on every PR instead. CI runs it on the Mac and iPhone apps it builds, the finish gate on
# the Mac app. Each Mach-O file's imported symbols (nm -u) and Objective-C selector names (otool) are matched against the
# table below, and each category found must be in the NSPrivacyAccessedAPITypes, with a reason, of the bundle the file
# sits in. Debug builds keep their code in *.debug.dylib, which is read like any other Mach-O file.
#
#   scripts/check-privacy-manifests.sh <path/to/App.app>...
#
# Exit 0 with one summary line when every use is declared; 1 with one line per missing declaration (the bundle, the
# category, the file and the symbol that uses it); 2 when an argument isn't a bundle with code, or a file can't be read.
set -euo pipefail

# Apple's required-reason APIs, by category (NSPrivacyAccessedAPICategory<category>): an imported symbol (sym) or an
# Objective-C selector (sel), as an extended regex. Source:
# https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
# CACurrentMediaTime isn't on Apple's list, but it reads mach_absolute_time, so #232 declares it as boot time (35F9.1).
# getattrlist and its variants read both file timestamps and disk space, so Apple lists them under both.
rules='
UserDefaults     sym  ^_OBJC_CLASS_[$]_NSUserDefaults$
SystemBootTime   sym  ^_mach_absolute_time$
SystemBootTime   sym  ^_CACurrentMediaTime$
SystemBootTime   sel  ^systemUptime$
FileTimestamp    sym  ^_[fl]?stat(at)?(64)?([$]INODE64)?$
FileTimestamp    sym  ^_f?getattrlist(at|bulk)?$
FileTimestamp    sym  ^_NSFile(Creation|Modification)Date$
FileTimestamp    sym  ^_NSURL(ContentModification|Creation)DateKey$
FileTimestamp    sel  ^fileModificationDate$
DiskSpace        sym  ^_NSURLVolume(TotalCapacity|AvailableCapacity(ForImportantUsage|ForOpportunisticUsage)?)Key$
DiskSpace        sym  ^_NSFileSystem(Free)?Size$
DiskSpace        sym  ^_f?statv?fs(64)?([$]INODE64)?$
DiskSpace        sym  ^_f?getattrlist(at)?$
ActiveKeyboards  sel  ^activeInputModes$
'

[ $# -gt 0 ] || { echo "usage: $0 <path/to/App.app>..." >&2; exit 2; }

# Prints "sym <name>" for each symbol a Mach-O file imports and "sel <name>" for each Objective-C selector it names
# (both architectures of a universal file; duplicates are harmless).
uses() {
  nm -u -j "$1" 2>/dev/null | awk 'NF == 1 && !/:$/ { print "sym " $1 }' &&
    otool -v -s __TEXT __objc_methname "$1" | sed -nE 's/^[0-9a-f]+[[:space:]]+([^[:space:]]+)$/sel \1/p'
}

# Reads uses() lines; prints "<category><tab><symbol>" for each line a rule matches.
categorize() {
  RULES="$rules" awk '
    BEGIN {
      n = split(ENVIRON["RULES"], lines, "\n")
      for (i = 1; i <= n; i++) if (split(lines[i], f, " ") == 3) { cat[++r] = f[1]; kind[r] = f[2]; re[r] = f[3] }
    }
    { for (i = 1; i <= r; i++) if ($1 == kind[i] && $2 ~ re[i]) print cat[i] "\t" $2 }'
}

# The bundle's own manifest: iOS keeps it at the bundle's top, macOS in Resources (Versions/A/Resources in a framework).
manifest_of() {
  local m
  for m in "$1/PrivacyInfo.xcprivacy" "$1/Contents/Resources/PrivacyInfo.xcprivacy" "$1/Resources/PrivacyInfo.xcprivacy" \
    "$1/Versions/A/Resources/PrivacyInfo.xcprivacy"; do
    if [ -f "$m" ]; then echo "$m"; return 0; fi
  done
  return 0
}

# Prints each category a manifest declares with at least one reason.
declared() {
  local n i
  n=$(plutil -extract NSPrivacyAccessedAPITypes raw -o - "$1" 2>/dev/null) || return 0
  case "$n" in '' | *[!0-9]*) return 0 ;; esac
  for ((i = 0; i < n; i++)); do
    if plutil -extract "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPITypeReasons.0" raw -o - "$1" >/dev/null 2>&1; then
      plutil -extract "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPIType" raw -o - "$1" 2>/dev/null |
        sed 's/^NSPrivacyAccessedAPICategory//' || true
    fi
  done
  return 0
}

# Every Mach-O file in the arguments, as "<bundle it belongs to><tab><file>": the innermost app, extension, framework,
# XPC service or loadable bundle around it, each of which carries its own manifest.
owned=""
for top in "$@"; do
  top="${top%/}"
  [ -d "$top" ] || { echo "error: $top isn't a bundle" >&2; exit 2; }
  nested=$(find "$top" -mindepth 1 -type d \( -name '*.app' -o -name '*.appex' -o -name '*.framework' -o -name '*.xpc' \
    -o -name '*.bundle' -o -name '*.plugin' \))
  found=0
  while IFS= read -r f; do
    case "$(file -b --mime-type "$f")" in *x-mach-binary*) ;; *) continue ;; esac
    owner="$top"
    while IFS= read -r b; do
      case "$f" in "$b"/*) [ ${#b} -le ${#owner} ] || owner="$b" ;; esac
    done <<<"$nested"
    owned+="$owner"$'\t'"$f"$'\n'
    found=1
  done < <(find "$top" -type f -perm -u+x)
  [ "$found" = 1 ] || { echo "error: $top has no Mach-O file; pass a built .app" >&2; exit 2; }
done

missing=0
summary=""
bundles=$(printf '%s' "$owned" | cut -f1 | sort -u)
while IFS= read -r bundle; do
  # The first file and symbol that use each category in this bundle.
  uses_here=""
  while IFS=$'\t' read -r owner f; do
    [ "$owner" = "$bundle" ] || continue
    u=$(uses "$f") || { echo "error: can't read the symbols of $f" >&2; exit 2; }
    uses_here+=$(printf '%s\n' "$u" | categorize | awk -v file="${f##*/}" -F '\t' '{ print $1 "\t" $2 "\t" file }')$'\n'
  done <<<"$owned"
  uses_here=$(printf '%s' "$uses_here" | awk -F '\t' 'NF == 3 && !seen[$1]++')
  [ -n "$uses_here" ] || { summary+="${summary:+; }$bundle: none"; continue; }

  manifest=$(manifest_of "$bundle")
  have=""
  if [ -z "$manifest" ]; then
    why=": the bundle has no PrivacyInfo.xcprivacy"
  elif ! plutil -lint -s "$manifest" >/dev/null 2>&1; then
    why=": its PrivacyInfo.xcprivacy isn't a valid property list"
  else
    why=" in its PrivacyInfo.xcprivacy"
    have=$(declared "$manifest")
  fi
  cats=""
  while IFS=$'\t' read -r cat sym bin; do
    cats+="${cats:+, }$cat"
    case $'\n'"$have"$'\n' in
      *$'\n'"$cat"$'\n'*) ;;
      *) echo "$bundle: NSPrivacyAccessedAPICategory$cat isn't declared$why ($bin uses $sym)"; missing=$((missing + 1)) ;;
    esac
  done <<<"$uses_here"
  summary+="${summary:+; }$bundle: $cats"
done <<<"$bundles"

if [ "$missing" -gt 0 ]; then
  echo "privacy manifests: $missing missing; add each, with Apple's reason, to that bundle's PrivacyInfo.xcprivacy"
  exit 1
fi
echo "privacy manifests: ok, every required-reason API used is declared ($summary)"
