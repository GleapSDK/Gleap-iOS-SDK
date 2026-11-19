#!/bin/sh
# Compiler and static analyzer warnings of the SDK target (xcodebuild analyze), plus two warnings the shipped build does
# not turn on: a nullable value passed where nonnull is required, and self retained implicitly in a block. They are set
# on this command line only; Package.swift and the podspec stay as they are. Clean every time: Xcode does not repeat the
# warnings of a file it analyzed in an earlier run.
#   sh scripts/analyze.sh          every warning, old code included (make analyze, for reading)
#   sh scripts/analyze.sh <log>    only writes xcodebuild's output to <log>; scripts/lint-new.sh filters it
root=$(git rev-parse --show-toplevel) || exit 3
cd "$root" || exit 3
mkdir -p build/analyze || exit 3
log=${1:-build/analyze/xcodebuild.log}
xcodebuild -scheme Gleap -destination 'generic/platform=iOS Simulator' -derivedDataPath build/analyze/DerivedData -quiet \
  CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF=YES 'OTHER_CFLAGS=$(inherited) -Wnullable-to-nonnull-conversion' \
  clean analyze >"$log" 2>&1
code=$?
if [ $# -eq 0 ]; then
  grep -E ': (warning|error): ' "$log" | sed "s#^$root/##" | sort -u
  echo "$(grep -cE ': (warning|error): ' "$log" | tr -d ' ') lines in $log"
fi
exit "$code"
