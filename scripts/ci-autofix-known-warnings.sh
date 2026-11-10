#!/usr/bin/env bash
# Bounded, source-wide fixes for compiler diagnostics with a proven semantics-preserving rewrite.
set -Eeo pipefail
LOG_FILE="${1:-}"
if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
  echo "Usage: $0 <build-log>" >&2
  exit 2
fi

if ! grep -Fq '[-Wrestrict]' "$LOG_FILE"; then
  echo "No supported -Wrestrict diagnostic found; refusing to guess."
  exit 1
fi

python3 - <<'PY'
from pathlib import Path

root = Path("drivers/net/wireless/rockchip_wlan")
old = 'rtw_sprintf(thread_name, 20, "%s-"ADPT_FMT, thread_name, ADPT_ARG(padapter));'
new = 'rtw_sprintf(thread_name, 20, "RTWHALXT-"ADPT_FMT, ADPT_ARG(padapter));'
changed = []
occurrences = 0
for path in root.rglob("*.c"):
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count:
        path.write_text(source.replace(old, new), encoding="utf-8")
        changed.append((str(path), count))
        occurrences += count

if occurrences == 0:
    raise SystemExit("-Wrestrict was present, but no known-safe thread_name overlap pattern was found")

remaining = []
for path in root.rglob("*.c"):
    if old in path.read_text(encoding="utf-8"):
        remaining.append(str(path))
if remaining:
    raise SystemExit("Unfixed overlapping thread_name calls remain: " + ", ".join(remaining))

print(f"Applied {occurrences} semantics-preserving thread-name fixes across {len(changed)} source files:")
for path, count in changed:
    print(f"  {path}: {count}")
PY
