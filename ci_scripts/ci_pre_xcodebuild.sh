#!/bin/sh
set -eu
cd "$(dirname "$0")"

# Seed SwiftPM's macro approvals on each ephemeral Xcode Cloud build machine.
python3 - "${SWIFTPM_SECURITY_DIR:-$HOME/Library/org.swift.swiftpm/security}" <<'PY'
import json
import sys
from pathlib import Path

targets = {
    "swift-case-paths": "CasePathsMacros",
    "swift-composable-architecture": "ComposableArchitectureMacros",
    "swift-dependencies": "DependenciesMacrosPlugin",
    "swift-navigation": "SwiftNavigationMacros",
    "swift-perception": "PerceptionMacros",
}
pins = {pin["identity"]: pin for pin in json.loads(Path("Package.resolved").read_text())["pins"]}
path = Path(sys.argv[1]) / "macros.json"
approvals = json.loads(path.read_text()) if path.exists() else []
for package, target in targets.items():
    pin = pins[package]
    if pin["location"].removesuffix(".git") != f"https://github.com/pointfreeco/{package}":
        sys.exit(f"Unexpected source for macro package {package}")
    entry = {"packageIdentity": package, "targetName": target, "fingerprint": pin["state"]["revision"]}
    approvals = [item for item in approvals if (item["packageIdentity"], item["targetName"]) != (package, target)]
    approvals.append(entry)
path.parent.mkdir(parents=True, exist_ok=True)
temporary = path.with_suffix(".tmp")
temporary.write_text(json.dumps(approvals, indent=2))
temporary.replace(path)
print(f"Configured {len(targets)} Swift macro approvals from Package.resolved.")
PY
