#!/bin/sh
# Judges only what a branch adds to its base; old code is never judged. Run by make lint-new, git push
# (.githooks/pre-push), the stop hook and the Quality workflow:
#   1. size: a file under Sources/ that ends up over 700 lines must not have grown
#   2. clang-format (.clang-format) on the .h and .m files the branch adds; old files keep their own style
#   3. the public API (scripts/api-check.sh), when a header in Sources/ObjCSources changed
#   4. compiler and static analyzer warnings (scripts/analyze.sh) on the lines the branch adds or changes in Sources/
# Uncommitted and untracked files count as part of the branch.
#   sh scripts/lint-new.sh [base]    base defaults to origin/main
# Exit codes: 0 clean, 1 problems found, 3 a check could not run.
base=${1:-origin/main}
tools=$(cd "$(dirname "$0")" && pwd)
config=${LINT_CLANG_FORMAT_CONFIG:-$tools/../.clang-format}
root=$(git rev-parse --show-toplevel) || exit 3
cd "$root" || exit 3
fork=$(git merge-base "$base" HEAD) || {
  echo "lint-new: no merge base with $base (git fetch origin?)" >&2
  exit 3
}
work=build/lint-new
mkdir -p "$work" || exit 3
tab=$(printf '\t')
max_lines=700
problems=0
broken=0

annotate() { # path, line, message: an annotation on the PR's diff in GitHub Actions
  [ "${GITHUB_ACTIONS:-}" = true ] || return 0
  printf '::error file=%s,line=%s::%s\n' "$1" "$2" "$(printf '%s' "$3" | sed 's/%/%25/g')"
}

# status, old path, new path of every .h and .m file under Sources/ the branch adds, changes or renames.
{
  git diff --name-status -M --diff-filter=AMR "$fork" -- 'Sources/*.h' 'Sources/*.m' |
    awk -F "$tab" '{ print substr($1, 1, 1) "\t" $2 "\t" ($3 == "" ? $2 : $3) }'
  git ls-files -o --exclude-standard -- 'Sources/*.h' 'Sources/*.m' | awk '{ print "A\t-\t" $0 }'
} >"$work/changes"

# 1. Size.
while IFS="$tab" read -r status old path; do
  [ -f "$path" ] || continue
  now=$(wc -l <"$path" | tr -d ' ')
  [ "$now" -gt "$max_lines" ] || continue
  before=0
  [ "$status" = A ] || before=$(git show "$fork:$old" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$now" -gt "$before" ]; then
    echo "$path: $now lines (was $before). Over $max_lines lines a file must not grow: put the new code in a new file (.claude/rules/code-conventions.md)."
    annotate "$path" 1 "$now lines (was $before); over $max_lines lines a file must not grow"
    problems=$((problems + 1))
  fi
done <"$work/changes"

# 2. Formatting of added files.
while IFS="$tab" read -r status old path; do
  [ "$status" = A ] && [ -f "$path" ] || continue
  if ! output=$(sh "$tools/clang-format.sh" --style="file:$config" --dry-run --Werror "$path" 2>&1); then
    if printf '%s\n' "$output" | grep -q 'code should be clang-formatted'; then
      echo "$path: a new file follows .clang-format. Run: sh scripts/clang-format.sh -i $path"
      annotate "$path" 1 "A new file follows .clang-format: sh scripts/clang-format.sh -i $path"
      problems=$((problems + 1))
    else
      printf '%s\nlint-new: clang-format could not run on %s\n' "$output" "$path"
      broken=1
    fi
  fi
done <"$work/changes"

# 3. Public API.
if [ -n "$({ git diff --name-only "$fork" -- 'Sources/ObjCSources/*.h'; git ls-files -o --exclude-standard -- 'Sources/ObjCSources/*.h'; })" ]; then
  sh "$tools/api-check.sh" "$base"
  case $? in
    0) ;;
    1) problems=$((problems + 1)) ;;
    *) broken=1 ;;
  esac
fi

# 4. Warnings on added and changed lines.
if [ -s "$work/changes" ]; then
  sh "$tools/analyze.sh" "$work/analyze.log"
  analyzed=$?
  # path:line for every line the branch adds or changes; untracked files count in full.
  {
    git diff -U0 --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ -M --diff-filter=AMR "$fork" -- 'Sources/*.h' 'Sources/*.m' | awk '
      /^\+\+\+ / { file = substr($2, 3); next }
      /^@@/ {
        split(substr($3, 2), range, ",")
        count = (range[2] == "" ? 1 : range[2])
        for (i = 0; i < count; i++) print file ":" range[1] + i
      }'
    git ls-files -o --exclude-standard -- 'Sources/*.h' 'Sources/*.m' | while read -r path; do
      awk -v file="$path" '{ print file ":" NR }' "$path"
    done
  } >"$work/changed-lines"
  grep -E ': (warning|error): ' "$work/analyze.log" | sed "s#^$root/##" | sort -u >"$work/diagnostics"
  awk -F : 'NR == FNR { changed[$1 ":" $2] = 1; next } ($1 ":" $2) in changed' "$work/changed-lines" "$work/diagnostics" >"$work/new-diagnostics"
  if [ -s "$work/new-diagnostics" ]; then
    echo "Warnings on lines this branch adds or changes (scripts/analyze.sh):"
    cat "$work/new-diagnostics"
    while IFS=: read -r path line _ message; do
      annotate "$path" "$line" "${message# }"
    done <"$work/new-diagnostics"
    problems=$((problems + $(wc -l <"$work/new-diagnostics")))
  elif [ "$analyzed" -ne 0 ]; then
    # The build failed: an error in code the branch did not touch, or no Xcode at all.
    grep -E ': error: ' "$work/diagnostics" || tail -n 20 "$work/analyze.log"
    if grep -qE ': error: ' "$work/diagnostics"; then
      problems=$((problems + 1))
    else
      echo "lint-new: xcodebuild analyze could not run (exit $analyzed), see $work/analyze.log"
      broken=1
    fi
  fi
fi

if [ "$problems" -gt 0 ]; then
  echo "lint-new: $problems problem(s) in what this branch adds compared with $base."
  exit 1
fi
[ "$broken" = 0 ] || exit 3
echo "lint-new: nothing new to report compared with $base."
