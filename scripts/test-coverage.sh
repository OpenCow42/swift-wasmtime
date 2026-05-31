#!/usr/bin/env bash
set -euo pipefail

threshold="${COVERAGE_THRESHOLD:-100}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if [[ -d /Applications/Xcode.app/Contents/Developer && -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$root/.build/clang-module-cache}"

swift test --enable-code-coverage
coverage_json="$(swift test --show-codecov-path)"

python3 - "$coverage_json" "$threshold" <<'PY'
import json
import sys

coverage_path = sys.argv[1]
threshold = float(sys.argv[2])

with open(coverage_path, encoding="utf-8") as handle:
    report = json.load(handle)

covered = 0
count = 0
ignored = 0
for item in report["data"][0]["files"]:
    filename = item["filename"]
    if "/Sources/Wasmtime/" not in filename:
        continue
    summary = item["summary"]["lines"]
    covered += summary["covered"]
    count += summary["count"]
    with open(filename, encoding="utf-8") as source:
        ignored += sum(1 for line in source if "coverage:ignore" in line)

effective_count = max(count - ignored, 0)
effective_covered = min(covered, effective_count)
percentage = 100.0 if effective_count == 0 else effective_covered * 100.0 / effective_count
print(f"Sources/Wasmtime line coverage: {percentage:.2f}% ({effective_covered}/{effective_count}, {ignored} ignored)")
if percentage + 1e-9 < threshold:
    raise SystemExit(f"coverage {percentage:.2f}% is below required {threshold:.2f}%")
PY
