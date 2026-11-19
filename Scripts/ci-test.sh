#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
device_family="${1:-iPhone}"
result_path="${2:-TestResults.xcresult}"
sdk_version=$(xcrun --sdk iphonesimulator --show-sdk-version)
device_id=$(xcrun simctl list devices available --json | python3 -c '
import json,sys
family=sys.argv[1]
sdk=tuple(int(n) for n in sys.argv[2].split(".")[:2])
runtimes = [(runtime, devices) for runtime, devices in json.load(sys.stdin)["devices"].items()
            if ".iOS-" in runtime]
for runtime, devices in sorted(runtimes, key=lambda item: tuple(
        int(n) for n in item[0].split(".iOS-")[1].split("-")), reverse=True):
    version=tuple(int(n) for n in runtime.split(".iOS-")[1].split("-")[:2])
    if version > sdk: continue
    matches=[d for d in devices if d["name"].startswith(family) and d.get("isAvailable")]
    if matches:
        print("Using", runtime, matches[0]["name"], file=sys.stderr)
        print(matches[0]["udid"]); break
else: sys.exit("No available iOS simulator for " + family)
' "$device_family" "$sdk_version")
# Finish first-boot setup before XCTest tries to launch the app. Bound this
# separately so an unhealthy simulator cannot consume the entire job timeout.
python3 - "$device_id" <<'PYBOOT'
import subprocess, sys
try:
    subprocess.run(["xcrun", "simctl", "bootstatus", sys.argv[1], "-b"],
                   check=True, timeout=600)
except subprocess.TimeoutExpired:
    sys.exit("Simulator did not finish booting within 600 seconds")
PYBOOT
xcodebuild -project PocketIELTS.xcodeproj -scheme PocketIELTS \
  -destination "platform=iOS Simulator,id=$device_id,arch=$(uname -m)" \
  -derivedDataPath "${CI_DERIVED_DATA:-build}" \
  -resultBundlePath "$result_path" \
  -parallel-testing-enabled NO \
  -skipMacroValidation \
  -disableAutomaticPackageResolution \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
