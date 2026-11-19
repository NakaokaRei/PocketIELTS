#!/usr/bin/env python3
"""Reject missing translations and unsafe format substitutions in shipped catalogs."""
import json
import re
from pathlib import Path

LANGUAGES = {'en', 'ja', 'zh-Hans', 'zh-Hant', 'ko', 'es', 'pt-BR', 'vi', 'id', 'th', 'hi', 'ar'}
ROOT = Path(__file__).resolve().parents[1]
errors = []
for path in (ROOT / 'Resources').glob('*.xcstrings'):
    catalog = json.loads(path.read_text())
    for key, entry in catalog['strings'].items():
        if entry.get('shouldTranslate') is False:
            continue
        placeholders = sorted(re.findall(r'%(?:\d+\$)?(?:@|ld|lld|d|f|%)', key))
        for language in LANGUAGES:
            unit = entry.get('localizations', {}).get(language, {}).get('stringUnit', {})
            value = unit.get('value')
            if value is None or (key and not value):
                # The source-language key is itself a valid untranslated source value.
                if language == catalog['sourceLanguage'] and not re.search(r'[\u3040-\u30ff\u3400-\u9fff]', key):
                    value = key
                else:
                    errors.append(f'{path.name}: missing {language}: {key!r}')
                    continue
            if path.name == 'Localizable.xcstrings' and placeholders != sorted(re.findall(r'%(?:\d+\$)?(?:@|ld|lld|d|f|%)', value)):
                errors.append(f'{path.name}: format mismatch {language}: {key!r}')
if errors:
    raise SystemExit('\n'.join(errors))
print('Localization coverage and format placeholders passed for 12 languages.')
