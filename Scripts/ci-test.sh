#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
device_family="${1:-iPhone}"
result_path="${2:-TestResults.xcresult}"
device_id=$(xcrun simctl list devices available --json | python3 -c '
import json,sys
family=sys.argv[1]
for runtime, devices in reversed(list(json.load(sys.stdin)["devices"].items())):
    if ".iOS-" not in runtime: continue
    matches=[d for d in devices if d["name"].startswith(family) and d.get("isAvailable")]
    if matches:
        print(matches[0]["udid"]); break
else: sys.exit("No available iOS simulator for " + family)
' "$device_family")
xcodebuild -project PocketIELTS.xcodeproj -scheme PocketIELTS \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "${CI_DERIVED_DATA:-build}" \
  -resultBundlePath "$result_path" \
  -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO test
