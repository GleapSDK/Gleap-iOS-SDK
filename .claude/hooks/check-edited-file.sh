#!/bin/sh
# After every edit of an Objective-C or Swift file: a syntax check of that file (seconds), and clang-format for a .h or
# .m file under Sources/ the branch adds; old files keep their own style. Warnings, the API check and the tests wait for
# the stop hook. Exit 2 with stderr reaches the agent; a note on exit 0 goes out as JSON, since plain stdout reaches
# no one.
command -v jq >/dev/null 2>&1 || exit 0
file=$(jq -r '.tool_input.file_path // empty')
case "$file" in *.h | *.m | *.swift) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

# The file's own worktree, whichever one it is in.
root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
path=${file#"$root"/}
[ -f scripts/clang-format.sh ] || exit 0

note=
case "$path" in
  Sources/*.h | Sources/*.m)
    fork=$(git merge-base origin/main HEAD 2>/dev/null)
    added=$( (git diff --name-status -M --diff-filter=A "$fork" -- 'Sources/*.h' 'Sources/*.m' | cut -f 2;
      git ls-files -o --exclude-standard -- 'Sources/*.h' 'Sources/*.m') 2>/dev/null | grep -Fx "$path")
    if [ -n "$fork" ] && [ -n "$added" ]; then
      before=$(cksum <"$path")
      if ! output=$(sh scripts/clang-format.sh -i "$path" 2>&1); then
        printf 'The edit is on disk, but clang-format could not format %s:\n%s\n' "$path" "$output" >&2
        exit 2
      fi
      [ "$(cksum <"$path")" = "$before" ] ||
        note="clang-format reformatted $path, a file this branch adds. Read it again before the next edit."
    fi
    # A header is checked through a file that imports it.
    case "$path" in
      *.m) problems=$(xcrun --sdk iphonesimulator clang -fsyntax-only -fobjc-arc -fmodules -fmodules-cache-path=build/module-cache \
        -target arm64-apple-ios15.0-simulator -I Sources/ObjCSources -I Sources/Internal "$path" 2>&1)
        status=$? ;;
      *) problems=$(printf '#import "%s"\n' "$root/$path" | xcrun --sdk iphonesimulator clang -fsyntax-only -fobjc-arc -fmodules \
        -fmodules-cache-path=build/module-cache -target arm64-apple-ios15.0-simulator -I Sources/ObjCSources -I Sources/Internal \
        -x objective-c - 2>&1)
        status=$? ;;
    esac
    ;;
  *.swift)
    problems=$(xcrun swiftc -parse "$path" 2>&1)
    status=$?
    ;;
  *) exit 0 ;;
esac

if [ "$status" -ne 0 ]; then
  printf 'The edit is on disk, but %s does not compile. Fix it before you continue:\n%s\n%s\n' \
    "$path" "$(printf '%s\n' "$problems" | grep -E 'error' | head -n 20)" "$note" >&2
  exit 2
fi
[ -z "$note" ] || jq -n --arg note "$note" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $note}}'
exit 0
