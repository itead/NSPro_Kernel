#!/bin/sh
if [ "$#" -gt 1 ]; then printf 'Usage: %s [fichier-log]\n' "$0" >&2; exit 2; fi
if [ "$#" -eq 1 ]; then LOG_FILE=$1; else LOG_FILE=$(ls -1t ./nspanel-kernel-build-*.log 2>/dev/null | sed -n '1p'); fi
if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then printf 'Aucun log NSPanel valide trouvé.\n' >&2; exit 2; fi
printf '===== Analyse exhaustive du log : %s =====\n' "$LOG_FILE"
BUILD_STATUS=$(sed -n 's/^===== BUILD EXIT STATUS: \([0-9][0-9]*\) =====$/\1/p' "$LOG_FILE" | tail -n 1)
if [ -n "$BUILD_STATUS" ]; then
    if [ "$BUILD_STATUS" -eq 0 ]; then echo 'État compilation : succès.'; else echo "État compilation : échec (code $BUILD_STATUS)."; fi
else echo 'État compilation : en cours ou interrompue.'; fi
printf '\n===== Tous les diagnostics (aucune limite de résultats) =====\n'
if grep -n -B 5 -A 10 -E 'warning:|error:|fatal error:|undefined reference|Error [0-9]+' "$LOG_FILE"; then :
else echo 'Aucun diagnostic correspondant trouvé.'; fi
printf '\n===== Comptage =====\n'
printf 'Warnings : '; grep -Ec 'warning:' "$LOG_FILE" || true
printf 'Erreurs : '; grep -Ec 'error:|fatal error:|undefined reference|Error [0-9]+' "$LOG_FILE" || true
