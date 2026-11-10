#!/bin/sh
# Detached build with a single-build lock and automatic log publication.

BUILD_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
cd "$BUILD_DIR" || exit 1

for tool in make flock aarch64-unknown-linux-gnu-gcc; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Outil requis absent : %s\n' "$tool" >&2
        exit 1
    fi
done

LOCK_FILE="$BUILD_DIR/.nspanel-build.lock"
PID_FILE="$BUILD_DIR/.nspanel-build.pid"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    printf 'Une compilation NSPanel est déjà active (verrou %s).\n' "$LOCK_FILE" >&2
    exit 1
fi

LOG_FILE="$BUILD_DIR/nspanel-kernel-build-$(date '+%Y%m%d-%H%M%S')-$$.log"
{
    printf '===== NSPanel kernel build started: %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf '===== Working directory: %s =====\n' "$BUILD_DIR"
    printf '===== Host: %s =====\n' "$(hostname -f 2>/dev/null || hostname)"
    printf '===== Commit: %s =====\n' "$(git rev-parse HEAD 2>/dev/null || printf unknown)"
    printf '===== Compiler: %s =====\n' "$(aarch64-unknown-linux-gnu-gcc -dumpfullversion)"
} > "$LOG_FILE"

(
    trap '' HUP
    trap 'rm -f "$PID_FILE"' EXIT
    ARCH=arm64 CROSS_COMPILE=aarch64-unknown-linux-gnu- make -j3 \
        HOSTCFLAGS="-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89 -fcommon" \
        Image dtbs modules >> "$LOG_FILE" 2>&1
    BUILD_STATUS=$?
    {
        printf '\n===== BUILD EXIT STATUS: %s =====\n' "$BUILD_STATUS"
        printf '===== NSPanel kernel build finished: %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    } >> "$LOG_FILE"

    if "$BUILD_DIR/NSPanel-commit-and-push.sh" "$LOG_FILE" >> "$LOG_FILE" 2>&1; then
        printf '===== LOG EXPORT STATUS: SUCCESS =====\n' >> "$LOG_FILE"
    else
        PUSH_STATUS=$?
        printf '===== LOG EXPORT STATUS: FAILED (%s) =====\n' "$PUSH_STATUS" >> "$LOG_FILE"
        exit "$PUSH_STATUS"
    fi
    exit "$BUILD_STATUS"
) </dev/null >/dev/null 2>&1 &
BUILD_PID=$!
printf '%s\n' "$BUILD_PID" > "$PID_FILE"

printf 'Compilation lancée en arrière-plan.\n'
printf 'PID : %s\n' "$BUILD_PID"
printf 'Log : %s\n' "$LOG_FILE"
printf 'Le log sera automatiquement commité et poussé à la fin du build.\n'
