#!/bin/sh
# Publish exactly one completed build log; do not commit unrelated work.

set -e
BUILD_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$BUILD_DIR"

if [ "$#" -gt 1 ]; then
    printf 'Usage: %s [fichier-log]\n' "$0" >&2
    exit 2
fi
if [ "$#" -eq 1 ]; then
    LOG_FILE=$1
else
    LOG_FILE=$(ls -1t ./nspanel-kernel-build-*.log 2>/dev/null | sed -n '1p')
fi
if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
    printf 'Aucun log de compilation valide à exporter.\n' >&2
    exit 2
fi

case "$LOG_FILE" in
    /*) LOG_PATH=$LOG_FILE ;;
    *) LOG_PATH="$BUILD_DIR/$LOG_FILE" ;;
esac
LOG_DIR=$(CDPATH= cd -- "$(dirname -- "$LOG_PATH")" && pwd)
LOG_PATH="$LOG_DIR/$(basename -- "$LOG_PATH")"

if ! grep -Eq '^===== BUILD EXIT STATUS: [0-9]+ =====$' "$LOG_PATH"; then
    printf 'Refus : le log ne contient pas de statut final de compilation.\n' >&2
    exit 2
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
case "$LOG_PATH" in
    "$REPO_ROOT"/*) REL_LOG=$(printf '%s\n' "$LOG_PATH" | sed "s|^$REPO_ROOT/||") ;;
    *) printf 'Le log doit se trouver dans le dépôt Git.\n' >&2; exit 2 ;;
esac

BRANCH=$(git symbolic-ref --quiet --short HEAD) || {
    printf 'Refus : HEAD détachée, branche cible indéterminée.\n' >&2
    exit 2
}
git add -- "$REL_LOG"
if git diff --cached --quiet -- "$REL_LOG"; then
    printf 'Log déjà présent dans Git : %s\n' "$REL_LOG"
    exit 0
fi
git -c core.hooksPath=/dev/null commit -m "Add NSPanel kernel build log" -- "$REL_LOG"

ATTEMPT=1
while [ "$ATTEMPT" -le 3 ]; do
    git fetch origin "$BRANCH"
    if ! git rebase --autostash "origin/$BRANCH"; then
        git rebase --abort
        printf 'Rebase impossible ; commit local conservé.\n' >&2
        exit 1
    fi
    if git push origin "HEAD:refs/heads/$BRANCH"; then
        printf 'Log publié sur origin/%s : %s\n' "$BRANCH" "$REL_LOG"
        exit 0
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 2
done
printf 'Push impossible après 3 tentatives ; commit local conservé.\n' >&2
exit 1
