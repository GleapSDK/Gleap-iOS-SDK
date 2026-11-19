#!/bin/sh
# The public API, as Swift sees it, of the headers in Sources/ObjCSources (both package managers publish all of them),
# compared with where the branch left its base. A removed or changed declaration breaks apps and the Flutter and React
# Native SDKs on their next update: it fails, and needs a major version (stop and ask). An added one is listed, to go
# into CHANGELOG.md. swift-api-digester comes with Xcode; nothing is built.
#   sh scripts/api-check.sh [base]    base defaults to origin/main
# Exit codes: 0 no breaking change, 1 breaking changes, 3 the check could not run.
base=${1:-origin/main}
root=$(git rev-parse --show-toplevel) || exit 3
cd "$root" || exit 3
fork=$(git merge-base "$base" HEAD) || {
  echo "api-check: no merge base with $base (git fetch origin?)" >&2
  exit 3
}
work="$root/build/api-check"
mkdir -p "$work/head" "$work/module-cache" || exit 3
# The base headers are kept per commit: fresh copies would make the module cache rebuild them (about 30 s).
base_headers="$work/base-$fork"
if [ ! -f "$base_headers/Sources/ObjCSources/Gleap.h" ]; then
  rm -rf "$work"/base-* && mkdir -p "$base_headers" &&
    git archive "$fork" Sources/ObjCSources | tar -x -C "$base_headers" || exit 3
fi
mkdir -p "$work/base" || exit 3
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path) || exit 3

dump() { # side, directory of Gleap.h
  map=$(printf 'module Gleap {\n  umbrella header "%s/Gleap.h"\n  export *\n}' "$2")
  [ "$(cat "$work/$1/module.modulemap" 2>/dev/null)" = "$map" ] || printf '%s\n' "$map" >"$work/$1/module.modulemap"
  if ! xcrun swift-api-digester -dump-sdk -module Gleap -o "$work/$1.json" -sdk "$sdk" \
    -target arm64-apple-ios15.0-simulator -I "$work/$1" -module-cache-path "$work/module-cache" >"$work/$1.log" 2>&1 ||
    [ "$(jq '[.ABIRoot.children[]?] | length' "$work/$1.json" 2>/dev/null || echo 0)" -eq 0 ]; then
    cat "$work/$1.log"
    echo "api-check: the $1 headers could not be read as the Gleap module"
    exit 3
  fi
}
dump base "$base_headers/Sources/ObjCSources"
dump head "$root/Sources/ObjCSources"

xcrun swift-api-digester -diagnose-sdk -input-paths "$work/base.json" -input-paths "$work/head.json" \
  >"$work/diagnose.txt" 2>&1 || {
  cat "$work/diagnose.txt"
  exit 3
}

# Declarations by their USR, for what the head adds.
declarations() {
  jq -r '[.. | objects | select(.usr? and .printedName?) | "\(.usr)\t\(.kind) \(.printedName)"] | unique[]' "$1"
}
declarations "$work/base.json" | cut -f 1 | sort -u >"$work/base.usr"
declarations "$work/head.json" | sort -u >"$work/head.decls"
added=$(awk -F '\t' 'NR == FNR { seen[$1] = 1; next } !($1 in seen) { print "  " $2 "  (" $1 ")" }' "$work/base.usr" "$work/head.decls")
if [ -n "$added" ]; then
  echo "Public API added (list it in CHANGELOG.md, and in README.md if it is a new call):"
  printf '%s\n' "$added"
  [ "${GITHUB_ACTIONS:-}" != true ] || echo "::notice title=Public API added::$(printf '%s' "$added" | tr '\n' ' ' | sed 's/%/%25/g')"
fi

broken=$(grep -vE '^[[:space:]]*$|^/\*' "$work/diagnose.txt")
if [ -n "$broken" ]; then
  echo "Public API removed or changed compared with $base (swift-api-digester):"
  printf '%s\n' "$broken"
  echo "Apps and the Flutter and React Native SDKs break on update. Add instead of changing, or stop and ask: this needs a major version."
  [ "${GITHUB_ACTIONS:-}" != true ] || echo "::error title=Public API removed or changed::$(printf '%s' "$broken" | tr '\n' ' ' | sed 's/%/%25/g')"
  exit 1
fi
echo "api-check: no public API removed or changed compared with $base."
