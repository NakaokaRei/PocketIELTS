#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_packages="${1:?Usage: generate-licenses.sh path/to/SourcePackages [output-directory]}"
output="${2:-Resources/Licenses}"
[[ -d "$source_packages/checkouts" ]] || { echo "error: Missing package checkouts: $source_packages. Resolve Swift packages first." >&2; exit 1; }
license_binary="$(Scripts/licenseplist-tool.sh)"
"$license_binary" --config-path license_plist.yml --package-sources-path "$source_packages" --output-path "$output" --force --no-color
rm -f "$output/Acknowledgements.latest_result.txt"
python3 Scripts/check-licenses.py "$output"
