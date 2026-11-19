#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_packages="${1:?Usage: generate-licenses.sh path/to/SourcePackages}"
license_binary="${LICENSE_PLIST_BIN:-license-plist}"
"$license_binary" --config-path license_plist.yml --package-sources-path "$source_packages" --output-path Resources/Licenses --force --no-color
# The runtime only consumes the generated plist index and license bodies.
rm -f Resources/Licenses/Acknowledgements.latest_result.txt
python3 Scripts/check-licenses.py
