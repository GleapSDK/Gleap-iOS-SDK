#!/usr/bin/env bash
# Runs the SDK's unit tests on the first available iPhone simulator.
set -euo pipefail

udid=$(xcrun simctl list devices available -j |
  jq -r '[.devices | to_entries[] | select(.key | contains("iOS")) | .value[] | select(.name | startswith("iPhone"))] | last | .udid')
if [ -z "$udid" ] || [ "$udid" = "null" ]; then
  echo "No iPhone simulator available" >&2
  exit 1
fi

# The result bundle keeps every failure's message, attachments and logs (-quiet prints only the
# failing test names); CI uploads it when the tests fail.
result_bundle="${TEST_RESULT_BUNDLE:-build/TestResults.xcresult}"
rm -rf "$result_bundle"
xcodebuild test -scheme Gleap -destination "platform=iOS Simulator,id=$udid" -resultBundlePath "$result_bundle" -quiet
