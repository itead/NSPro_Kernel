#!/bin/sh

if [ "$#" -gt 1 ]; then
	printf 'Usage: %s [fichier-log]\n' "$0" >&2
	exit 2
fi

if [ "$#" -eq 1 ]; then
	LOG_FILE=$1
else
	LOG_FILE=$(ls -1t ./nspanel-kernel-build-*.log 2>/dev/null | sed -n '1p')
fi

if [ -z "$LOG_FILE" ]; then
	printf 'Aucun log NSPanel trouvé dans le répertoire courant. Lance d’abord NSPanel-compile.sh.\n' >&2
	exit 2
fi

if [ ! -f "$LOG_FILE" ]; then
	printf 'Fichier log introuvable : %s\n' "$LOG_FILE" >&2
	exit 2
fi

printf '===== Analyse du log : %s =====\n' "$LOG_FILE"

BUILD_STATUS=$(sed -n 's/^===== BUILD EXIT STATUS: \([0-9][0-9]*\) =====$/\1/p' "$LOG_FILE" | tail -n 1)
if [ -n "$BUILD_STATUS" ]; then
	if [ "$BUILD_STATUS" -eq 0 ]; then
		printf 'État compilation : terminée avec succès.\n'
	else
		printf 'État compilation : échec (code %s).\n' "$BUILD_STATUS"
	fi
else
	printf 'État compilation : en cours ou log interrompu (aucun statut final).\n'
fi

if git rev-parse --show-toplevel >/dev/null 2>&1; then
	LOG_GIT_PATH=$(basename "$LOG_FILE")
	if git diff --cached --name-only | grep -F -x -- "$LOG_GIT_PATH" >/dev/null 2>&1; then
		printf 'État Git : log ajouté à l’index, prêt pour le prochain commit.\n'
	else
		printf 'État Git : log pas encore indexé (compilation éventuellement en cours).\n'
	fi
fi

printf '\n===== Diagnostics (warnings, erreurs et échecs make) =====\n'
if grep -n -B 8 -A 12 -m 20 -E 'warning:|error:|fatal error:|undefined reference|Error [0-9]' "$LOG_FILE"; then
	:
else
	printf 'Aucun diagnostic correspondant trouvé dans le log.\n'
fi
