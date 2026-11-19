#!/usr/bin/env python3
"""Rebuild the curated offline subset from unpacked Princeton WordNet 3.0 dict/.
Download: https://wordnetcode.princeton.edu/3.0/WNdb-3.0.tar.gz
Usage: python3 Scripts/import-wordnet.py /path/to/dict
Selection pins lexical senses; no network access or runtime dependency.
"""
import json
import pathlib
import re
import sys

repo = pathlib.Path(__file__).resolve().parents[1]
dictionary = pathlib.Path(sys.argv[1])
selection = json.loads((repo / 'Scripts/vocabulary-selection.json').read_text())
data = {}
for pos in ('noun', 'verb', 'adj'):
    data[pos] = {line.split()[0]: line.split('|', 1)[1].strip()
                 for line in (dictionary / f'data.{pos}').read_text().splitlines()
                 if not line.startswith(' ') and '|' in line}
rows = []
for entry in selection:
    offset, pos = entry['synset'].split('-')
    gloss = data[pos][offset]
    examples = re.findall(r'"([^"]+)"', gloss)
    # Prefer an example containing this lemma, rather than another synonym.
    example = next((x for x in examples if re.search(r'\b' + re.escape(entry['expression']) + r'\b', x, re.I)), '')
    rows.append(dict(expression=entry['expression'],
                     definition=re.split(r';?\s*"', gloss)[0].strip().rstrip(';'),
                     example=example, level=entry['level'], synset=entry['synset']))
assert len({r['expression'] for r in rows}) == len(rows)
(repo / 'Resources/Vocabulary/WordNet.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
print(f'Imported {len(rows)} pinned WordNet senses.')
