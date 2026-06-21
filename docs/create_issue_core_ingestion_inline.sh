#!/usr/bin/env bash
# Crea la issue pronta per agente per la feature "Core Ingestion inline".
# Prerequisiti:
#   1) gh installato
#   2) gh auth login con accesso a jackw1-tech/Mobility-Diary
# Esecuzione:
#   bash docs/create_issue_core_ingestion_inline.sh
set -euo pipefail

REPO="jackw1-tech/Mobility-Diary"

gh label create feature --repo "$REPO" --color 0e8a16 --description "Nuova funzionalita'" 2>/dev/null || true
gh label create backend --repo "$REPO" --color 1d76db --description "Back-end Django/PostGIS" 2>/dev/null || true
gh label create mobile --repo "$REPO" --color 5319e7 --description "App Flutter mobile/diary" 2>/dev/null || true
gh label create ready-for-agent --repo "$REPO" --color 2ea44f --description "Issue pronta per essere presa da un agente" 2>/dev/null || true

gh issue create --repo "$REPO" \
  --title "Core Ingestion inline sincrona per velocizzare la mappa del viaggio" \
  --label feature --label backend --label mobile --label ready-for-agent \
  --body-file PRD_CORE_INGESTION_INLINE.md

echo "Fatto. Issue creata su $REPO."
