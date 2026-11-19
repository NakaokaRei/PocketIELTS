"""Fail if a resolved package or bundled font is missing from LicensePlist output."""
import json
import pathlib
import plistlib
root = pathlib.Path(__file__).resolve().parent.parent
licenses = root / 'Resources/Licenses'
index = plistlib.loads((licenses / 'Acknowledgements.plist').read_bytes())
files = [row['File'] for row in index['PreferenceSpecifiers'] if row.get('Type') == 'PSChildPaneSpecifier']
resolved = json.loads((root / 'PocketIELTS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
expected = {pin['identity'] for pin in resolved['pins']} | {'Nunito', 'Zen Maru Gothic'}
actual = {pathlib.Path(name).name for name in files}
missing = expected - actual
assert not missing, f'Missing licenses: {sorted(missing)}'
for name in files:
    doc = plistlib.loads((licenses / (name + '.plist')).read_bytes())
    assert any(len(row.get('FooterText', '')) > 100 for row in doc['PreferenceSpecifiers']), name
print(f'Validated {len(files)} bundled OSS notices.')
