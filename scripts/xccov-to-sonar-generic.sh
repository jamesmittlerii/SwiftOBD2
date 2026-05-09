#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="coverage"
OUT_XML="$OUT_DIR/sonar-generic-coverage.xml"
mkdir -p "$OUT_DIR"

LCOV_FILE="$OUT_DIR/coverage.lcov"

PROFDATA=$(find .build swiftobd2/.build -name "*.profdata" -print -quit 2>/dev/null || true)
BINARY=$(find .build swiftobd2/.build -type f -perm -111 -name "*SwiftOBD2*" -print -quit 2>/dev/null || true)

if [[ -n "${PROFDATA}" && -n "${BINARY}" ]]; then
  echo "Found profdata: $PROFDATA"
  echo "Found binary:   $BINARY"
  xcrun llvm-cov export -format=lcov "$BINARY" -instr-profile "$PROFDATA" > "$LCOV_FILE" || true
else
  echo "Warning: Could not find profdata/binary automatically. Generating empty coverage placeholder for Sonar."
  printf "TN:\nSF:PLACEHOLDER.swift\nDA:1,0\nend_of_record\n" > "$LCOV_FILE"
fi

python3 - <<'PY'
import os, xml.etree.ElementTree as ET
from collections import defaultdict

lcov_path = os.path.join('coverage', 'coverage.lcov')
files = defaultdict(dict)
cur = None
if os.path.exists(lcov_path):
    with open(lcov_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line.startswith('SF:'):
                cur = line[3:]
            elif line.startswith('DA:') and cur:
                parts = line[3:].split(',')
                if len(parts) >= 2:
                    ln = int(parts[0]); hits = int(parts[1])
                    files[cur][ln] = hits
            elif line == 'end_of_record':
                cur = None

root = ET.Element('coverage', {'version': '1'})
for path, lines in files.items():
    if not any(seg in path for seg in ('swiftobd2/Sources/', 'swiftobd2/Source/')):
        continue
    if any(seg in path for seg in ('swiftobd2/Sources/SwiftOBD2/Communication/BLE/', 'swiftobd2/Sources/SwiftOBD2/Communication/wifiManager.swift')):
        continue
    f = ET.SubElement(root, 'file', {'path': path})
    for ln, hits in sorted(lines.items()):
        ET.SubElement(f, 'lineToCover', {
            'lineNumber': str(ln),
            'covered': 'true' if hits > 0 else 'false'
        })

ET.ElementTree(root).write(os.path.join('coverage','sonar-generic-coverage.xml'), encoding='utf-8', xml_declaration=True)
print('Wrote coverage/sonar-generic-coverage.xml')
PY

echo "Conversion complete: $OUT_XML"
