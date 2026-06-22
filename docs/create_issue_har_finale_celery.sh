#!/usr/bin/env bash
# Crea la issue pronta per agente per il PRD "HAR finale asincrono via Celery".
# Prerequisiti:
#   1) gh installato
#   2) gh auth login con accesso a jackw1-tech/Mobility-Diary
# Esecuzione:
#   bash docs/create_issue_har_finale_celery.sh
set -euo pipefail

REPO="jackw1-tech/Mobility-Diary"

gh label create feature --repo "$REPO" --color 0e8a16 --description "Nuova funzionalita'" 2>/dev/null || true
gh label create backend --repo "$REPO" --color 1d76db --description "Back-end Django/PostGIS" 2>/dev/null || true
gh label create mobile --repo "$REPO" --color 5319e7 --description "App Flutter mobile/diary" 2>/dev/null || true
gh label create ready-for-agent --repo "$REPO" --color 2ea44f --description "Issue pronta per essere presa da un agente" 2>/dev/null || true

gh issue create --repo "$REPO" \
  --title "PRD: HAR finale asincrono via Celery" \
  --label feature --label backend --label mobile --label ready-for-agent \
  --body-file PRD_HAR_FINALE_CELERY.md

echo "Fatto. Issue creata su $REPO."
