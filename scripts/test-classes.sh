#!/usr/bin/env bash
# Runs only the given XCTest classes of GleapTests, on the simulator .github/scripts/test.sh picks.
#   bash scripts/test-classes.sh GleapGrantTests GleapUserJwtTests      (make test-classes CLASSES="...")
# Several sessions share a machine and its simulators, and the tests write NSUserDefaults: run the classes your change
# reaches, never the whole suite while another one runs (AGENTS.md).
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Name the test classes: bash scripts/test-classes.sh GleapGrantTests [...]" >&2
  exit 2
fi
cd "$(git rev-parse --show-toplevel)"

udid=$(xcrun simctl list devices available -j |
  jq -r '[.devices | to_entries[] | select(.key | contains("iOS")) | .value[] | select(.name | startswith("iPhone"))] | last | .udid')
if [ -z "$udid" ] || [ "$udid" = "null" ]; then
  echo "No iPhone simulator available" >&2
  exit 1
fi

only=()
for class in "$@"; do
  only+=("-only-testing:GleapTests/$class")
done
result_bundle="build/TestResults-classes.xcresult"
rm -rf "$result_bundle"
xcodebuild test -scheme Gleap -destination "platform=iOS Simulator,id=$udid" "${only[@]}" -resultBundlePath "$result_bundle" -quiet
