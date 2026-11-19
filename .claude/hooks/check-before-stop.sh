#!/bin/sh
# Before a turn ends, once the branch changes SDK or test code: scripts/lint-new.sh (warnings on added and changed
# lines, formatting of added files, size, the public API; about 30 s) and the XCTest classes the change reaches: a
# changed test file, and <Name>Tests for a changed <Name>.m or <Name>.h. Red means the turn is not done. Never the whole
# suite: several sessions share this machine and its simulators, and CI runs it anyway.
command -v jq >/dev/null 2>&1 || exit 0
active=$(jq -r '.stop_hook_active // false')
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
[ -f scripts/lint-new.sh ] || exit 0

fork=$(git merge-base origin/main HEAD 2>/dev/null) || exit 0
changed=$( (git diff --name-only "$fork" -- Sources Tests .clang-format scripts; git ls-files -o --exclude-standard -- Sources Tests) 2>/dev/null | sort -u)
[ -n "$changed" ] || exit 0

# The agent was told once and changed nothing since: another block would only burn a turn.
state="$(git rev-parse --git-dir)/claude-stop-gate"
key=$( (git rev-parse HEAD; git diff HEAD; git ls-files -o --exclude-standard -- Sources Tests | xargs cat 2>/dev/null) | git hash-object --stdin)
if [ "$active" = true ] && [ "$(cat "$state" 2>/dev/null)" = "$key" ]; then
  exit 0
fi

# Test classes: those declared in a changed test file, and <Name>Tests for a changed source file <Name>.
test_files() {
  printf '%s\n' "$changed" | while read -r path; do
    case "$path" in
      Tests/GleapTests/*.swift) echo "$path" ;;
      Sources/*.m | Sources/*.h)
        name=$(basename "$path")
        echo "Tests/GleapTests/${name%.*}Tests.swift"
        ;;
    esac
  done
}
classes=$(test_files | sort -u | while read -r file; do
  [ ! -f "$file" ] || sed -nE 's/^(final )?class ([A-Za-z0-9_]+): *[A-Za-z]*TestCase.*/\2/p' "$file"
done | grep -v '^GleapNetworkTestCase$' | sort -u | tr '\n' ' ')

failures=
step() { # name, command...
  name=$1
  shift
  if ! output=$("$@" 2>&1 </dev/null); then
    failures="$failures
## $name
$(printf '%s\n' "$output" | grep -vE '^[[:space:]]*$' | tail -n 80)
"
  fi
}
step "sh scripts/lint-new.sh" sh scripts/lint-new.sh origin/main
# shellcheck disable=SC2086 # one argument per class
[ -z "$classes" ] || step "bash scripts/test-classes.sh $classes" bash scripts/test-classes.sh $classes

if [ -z "$failures" ]; then
  rm -f "$state"
  exit 0
fi
printf '%s\n' "$key" >"$state"
printf 'Fix this before you finish, or report BLOCKED with the reason:\n%s\n' "$failures" >&2
exit 2
