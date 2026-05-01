import json
import os

with open('../Sources/SwiftOBD2/Resources/codes.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

with open('lib/src/data/codes.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
