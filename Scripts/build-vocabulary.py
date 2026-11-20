#!/usr/bin/env python3
"""Build the reviewed General Training vocabulary. No downloads or API calls.
Each topic contains 100 original entries. Source TSV: word|meaning|example.
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOPICS = ['housing', 'work', 'training', 'shopping', 'travel', 'health', 'community', 'money', 'correspondence', 'society']
rows = []
seen = set()
for topic in TOPICS:
    lines = (ROOT / 'Scripts/Vocabulary' / f'{topic}.tsv').read_text().splitlines()
    assert len(lines) == 100, (topic, len(lines))
    for index, line in enumerate(lines):
        fields = line.split('|')
        assert len(fields) == 3 and all(x.strip() for x in fields), (topic, index)
        word, definition, example = fields
        assert word.casefold() not in seen, word
        seen.add(word.casefold())
        # Examples must actually use the target expression, allowing common inflections.
        assert word.casefold() in example.casefold(), (word, example)
        rows.append(dict(expression=word, definition=definition, example=example,
                         topic=topic, level=0 if index < 40 else 1 if index < 80 else 2))
assert len(rows) == 1000
output = ROOT / 'Resources/Vocabulary/GeneralTrainingWords.json'
output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
print(f'Validated {len(rows)} unique entries across {len(TOPICS)} topics, with meanings and examples.')
