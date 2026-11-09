#!/bin/sh

LOG_FILE="/tmp/nspanel-kernel-build-$(date '+%Y%m%d-%H%M%S')-$$.log"

{
	printf '===== NSPanel kernel build started: %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
	printf '===== Working directory: %s =====\n' "$PWD"
} > "$LOG_FILE"

(
	trap '' HUP
	ARCH=arm64 CROSS_COMPILE=aarch64-unknown-linux-gnu- make -j"$(nproc)" \
		HOSTCFLAGS="-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89 -fcommon" \
		Image dtbs modules >> "$LOG_FILE" 2>&1
	BUILD_STATUS=$?
	{
		printf '\n===== BUILD EXIT STATUS: %s =====\n' "$BUILD_STATUS"
		printf '===== NSPanel kernel build finished: %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
	} >> "$LOG_FILE"
	exit "$BUILD_STATUS"
) </dev/null >/dev/null 2>&1 &

BUILD_PID=$!
printf 'Compilation lancée en arrière-plan.\n'
printf 'PID : %s\n' "$BUILD_PID"
printf 'Log : %s\n' "$LOG_FILE"
