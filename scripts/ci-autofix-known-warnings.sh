#!/usr/bin/env bash
# Bounded, source-wide fixes for compiler diagnostics with a proven semantics-preserving rewrite.
set -Eeo pipefail
LOG_FILE="\${1:-}"
if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
  echo "Usage: $0 <build-log>" >&2
  exit 2
fi

HAS_RESTRICT=0
HAS_PACKED_SSID=0
grep -Fq '[-Wrestrict]' "$LOG_FILE" && HAS_RESTRICT=1 || true
grep -Fq '[-Waddress-of-packed-member]' "$LOG_FILE" && HAS_PACKED_SSID=1 || true
if [ "$HAS_RESTRICT" -eq 0 ] && [ "$HAS_PACKED_SSID" -eq 0 ]; then
  echo "No supported compiler diagnostic found; refusing to guess."
  exit 1
fi

if [ "$HAS_RESTRICT" -eq 1 ]; then
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
fi

if [ "$HAS_PACKED_SSID" -eq 1 ]; then
python3 - <<'PY'
from pathlib import Path

root = Path("drivers/net/wireless/rockchip_wlan")
old = "&pmlmeinfo->network.Ssid"
copy = (
    "\t/* WLAN_BSSID_EX is packed; copy SSID into aligned storage before use. */\n"
    "\tmemcpy(&aligned_network_ssid, (const u8 *)&pmlmeinfo->network +\n"
    "\t       offsetof(WLAN_BSSID_EX, Ssid), sizeof(aligned_network_ssid));\n\n"
)
changed = []
for path in root.glob("*/core/rtw_mlme_ext.c"):
    source = path.read_text(encoding="utf-8")
    if old not in source:
        continue
    fn = source.find("void linked_status_chk(")
    if fn < 0:
        raise SystemExit(f"Packed SSID reference outside expected function: {path}")
    decl = source.find("pmlmeinfo =", fn)
    if decl < 0:
        raise SystemExit(f"Cannot locate pmlmeinfo declaration: {path}")
    decl_end = source.find("\n", decl)
    declaration = "\tNDIS_802_11_SSID aligned_network_ssid;\n"
    if declaration not in source[fn:]:
        source = source[:decl_end + 1] + declaration + source[decl_end + 1:]
    assoc = source.find("if (is_client_associated_to_ap(padapter))", fn)
    if assoc < 0:
        raise SystemExit(f"Cannot locate associated-client guard: {path}")
    if copy not in source[fn:assoc]:
        source = source[:assoc] + copy + source[assoc:]
    count = source.count(old)
    source = source.replace(old, "&aligned_network_ssid")
    path.write_text(source, encoding="utf-8")
    changed.append((str(path), count))

remaining = [str(path) for path in root.rglob("*.c") if old in path.read_text(encoding="utf-8")]
if remaining:
    raise SystemExit("Packed SSID references remain: " + ", ".join(remaining))
if not changed:
    raise SystemExit("-Waddress-of-packed-member was present, but no known WLAN_BSSID_EX SSID pattern was found")

print(f"Aligned packed BSSID SSID access in {len(changed)} driver source files:")
for path, count in changed:
    print(f"  {path}: {count} call sites")
PY
fi
