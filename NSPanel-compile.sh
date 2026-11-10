#!/bin/sh
# The single entry point for local and GitHub Actions kernel builds.
BUILD_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
cd "$BUILD_DIR" || exit 1

CI_MODE=${NSPANEL_CI:-0}
if [ "$CI_MODE" != 1 ]; then
    # Synchronize the persistent checkout only when it is safe to fast-forward.
    BRANCH=$(git symbolic-ref --quiet --short HEAD) || {
        printf 'Refus : HEAD détachée, synchronisation impossible.\n' >&2; exit 1;
    }
    [ "$BRANCH" = "fix/rockchip-gem-zero-size" ] || {
        printf 'Refus : branche inattendue (%s).\n' "$BRANCH" >&2; exit 1;
    }
    if [ -n "$(git status --porcelain)" ]; then
        printf 'Refus : dépôt local modifié ; aucun git pull pour protéger les changements.\n' >&2
        git status --short >&2
        exit 1
    fi
    git fetch origin "$BRANCH" || exit 1
    git pull --ff-only origin "$BRANCH" || exit 1
    LOCAL_SHA=$(git rev-parse HEAD) || exit 1
    REMOTE_SHA=$(git rev-parse "origin/$BRANCH") || exit 1
    [ "$LOCAL_SHA" = "$REMOTE_SHA" ] || {
        printf 'Échec de synchronisation : HEAD=%s origin=%s\n' "$LOCAL_SHA" "$REMOTE_SHA" >&2
        exit 1
    }
fi

for tool in make flock aarch64-unknown-linux-gnu-gcc; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'Outil requis absent : %s\n' "$tool" >&2; exit 1; }
done
LOCK_FILE="$BUILD_DIR/.nspanel-build.lock"
PID_FILE="$BUILD_DIR/.nspanel-build.pid"
exec 9>"$LOCK_FILE"
flock -n 9 || { printf 'Une compilation NSPanel est déjà active.\n' >&2; exit 1; }

if [ "$CI_MODE" = 1 ]; then
    LOG_FILE=${NSPANEL_BUILD_LOG:-"$BUILD_DIR/nspanel-kernel-build-${GITHUB_RUN_ID:-manual}.log"}
    EXPECTED_SHA=${GITHUB_SHA:-}
    ACTUAL_SHA=$(git rev-parse HEAD) || exit 1
    [ -z "$EXPECTED_SHA" ] || [ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || {
        printf 'SHA checkout incorrect : attendu %s, obtenu %s\n' "$EXPECTED_SHA" "$ACTUAL_SHA" >&2
        exit 1
    }
    {
        printf '===== NSPanel build entry point: %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf '===== Working directory: %s =====\n' "$BUILD_DIR"
        printf '===== Commit initial: %s =====\n' "$ACTUAL_SHA"
        printf '===== Compiler: %s =====\n' "$(aarch64-unknown-linux-gnu-gcc -dumpfullversion)"
    } | tee -a "$LOG_FILE"
    BUILD_STATUS=1
    ATTEMPT=1
    while [ "$ATTEMPT" -le 3 ]; do
        echo "===== Kernel build attempt $ATTEMPT/3 =====" | tee -a "$LOG_FILE"
        set +e
        ARCH=arm64 CROSS_COMPILE=aarch64-unknown-linux-gnu- make -j3 \
            HOSTCFLAGS="-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89 -fcommon" \
            Image dtbs modules >> "$LOG_FILE" 2>&1
        BUILD_STATUS=$?
        set -e
        tail -n 80 "$LOG_FILE"
        if [ "$BUILD_STATUS" -eq 0 ]; then break; fi
        if [ "$ATTEMPT" -eq 3 ] || [ "${GITHUB_REF:-}" != "refs/heads/fix/rockchip-gem-zero-size" ]; then break; fi
        if ! bash scripts/ci-autofix-known-warnings.sh "$LOG_FILE"; then break; fi
        git diff --check || break
        if git diff --quiet; then break; fi
        git config user.name "github-actions[bot]"
        git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
        git add -- drivers/net/wireless/rockchip_wlan
        git commit -m "ci: apply verified Rockchip compiler warning fixes" || break
        git push origin "HEAD:$GITHUB_REF_NAME" || break
        echo "===== Repair committed: $(git rev-parse HEAD); retrying =====" | tee -a "$LOG_FILE"
        ATTEMPT=$((ATTEMPT + 1))
    done
    printf '\n===== BUILD EXIT STATUS: %s =====\n' "$BUILD_STATUS" | tee -a "$LOG_FILE"
    # The workflow runs the canonical analyzer once, writing to a separate report.
    # Never pipe analysis output back into the build log being scanned.
    exit "$BUILD_STATUS"
fi

LOG_FILE="$BUILD_DIR/nspanel-kernel-build-$(date '+%Y%m%d-%H%M%S')-$$.log"
{
    printf '===== NSPanel kernel build started: %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf '===== Working directory: %s =====\n' "$BUILD_DIR"
    printf '===== Host: %s =====\n' "$(hostname -f 2>/dev/null || hostname)"
    printf '===== Commit: %s =====\n' "$(git rev-parse HEAD)"
    printf '===== Compiler: %s =====\n' "$(aarch64-unknown-linux-gnu-gcc -dumpfullversion)"
} > "$LOG_FILE"
(
    trap '' HUP
    trap 'rm -f "$PID_FILE"' EXIT
    set +e
    ARCH=arm64 CROSS_COMPILE=aarch64-unknown-linux-gnu- make -j3 \
        HOSTCFLAGS="-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89 -fcommon" \
        Image dtbs modules >> "$LOG_FILE" 2>&1
    BUILD_STATUS=$?
    printf '\n===== BUILD EXIT STATUS: %s =====\n' "$BUILD_STATUS" >> "$LOG_FILE"
    "$BUILD_DIR/NSPanel-check-compile-errors.sh" "$LOG_FILE" >> "$LOG_FILE" 2>&1 || true
    "$BUILD_DIR/NSPanel-commit-and-push.sh" "$LOG_FILE" >> "$LOG_FILE" 2>&1 || exit $?
    exit "$BUILD_STATUS"
) </dev/null >/dev/null 2>&1 &
BUILD_PID=$!
printf '%s\n' "$BUILD_PID" > "$PID_FILE"
printf 'Compilation lancée en arrière-plan. PID : %s\nLog : %s\n' "$BUILD_PID" "$LOG_FILE"
