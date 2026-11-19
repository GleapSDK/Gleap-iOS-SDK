#!/bin/sh
# Runs the pinned clang-format (scripts/clang-format-requirements.txt) with the given arguments. The first run
# installs it into build/tools of the repository it is called from, a few seconds; nothing is installed globally.
#   sh scripts/clang-format.sh -i Sources/Internal/GleapNew.m
requirements="$(cd "$(dirname "$0")" && pwd)/clang-format-requirements.txt"
root=$(git rev-parse --show-toplevel) || exit 3
# One virtualenv per pinned version: a changed requirements file installs next to the old one.
venv="$root/build/tools/clang-format-$(cksum <"$requirements" | cut -d ' ' -f 1)"
if [ ! -x "$venv/bin/clang-format" ]; then
  rm -rf "$venv"
  mkdir -p "$root/build/tools" || exit 3
  if ! { python3 -m venv "$venv" &&
    "$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes -r "$requirements"; } >"$root/build/tools/install.log" 2>&1; then
    echo "clang-format could not be installed (python3 -m venv, pip): see build/tools/install.log" >&2
    rm -rf "$venv"
    exit 3
  fi
fi
exec "$venv/bin/clang-format" "$@"
