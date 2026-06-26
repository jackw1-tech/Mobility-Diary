# Mobile Export Testuale Del Diario Privacy-Aware

Status: ready-for-human

## Parent

.scratch/privacy-aware-diary/PRD.md

## What to build

Add the mobile "export diary" path as a text-only privacy-aware export. The normal mobile diary remains the Vista Privata del Diario. Export should call a dedicated backend path that returns an export-friendly Vista Privacy-Aware generated from the user's saved Preferenza Privacy.

The mobile UI should show a preview before sharing. The preview should clearly state the Livello Privacy, whether the output is protected or unprotected, and that any coordinates in non-precise levels are approximated coordinates rather than original GPS readings. v1 supports copy/simple text sharing only; no PDF, file export, or mobile comparison map.

## Acceptance criteria

- [ ] The backend exposes a dedicated mobile privacy export read model for a Viaggio.
- [ ] The export read model uses the user's saved Preferenza Privacy.
- [ ] The normal mobile diary endpoint remains private and precise.
- [ ] The export text includes the selected Livello Privacy.
- [ ] `precise` export is clearly marked as unprotected.
- [ ] `approximate` and `aggregated` exports use privacy-aware geometry and do not silently include precise GPS coordinates.
- [ ] Coordinates in non-precise exports are labeled as approximated.
- [ ] Significant stops in non-precise exports use generic wording rather than sensitive labels.
- [ ] The mobile app exposes an export action from the diary/trip experience.
- [ ] The mobile app shows a text preview before copy or simple share.
- [ ] Backend tests cover export contract and privacy behavior.
- [ ] Mobile tests cover service call, preview state, and absence of precise geometry in non-precise export text.

## Blocked by

- .scratch/privacy-aware-diary/issues/01-web-dashboard-privacy-aware-spatial-cloaking.md
- .scratch/privacy-aware-diary/issues/02-dashboard-privacy-levels-and-preview.md
- .scratch/privacy-aware-diary/issues/04-significant-places-privacy-aware-masking.md

## Comments

Implemented (local, no GitHub).

Backend
- New dedicated read model `GET /api/mobility/trips/{trip_id}/privacy-export`
  (`PrivacyExportOut`). The normal `/diary` endpoint is untouched (stays private
  and precise). The export uses the user's *saved* Preferenza Privacy and never
  mutates it.
- Response carries `level`, `protected`, `approximated_coordinates`,
  `cell_size_meters`, a pre-rendered `text`, and structured `segments`. MOVE
  segments expose cloaked coordinates for non-precise levels (never the original
  GPS readings); stops use the generic wording for non-precise and may show the
  real label only for `precise`. The text labels coordinates as approximated and
  marks `precise` as "NON protetta".

Mobile (Flutter)
- DTO `trip_privacy_export_dto.dart`, service
  `trip_privacy_export_service.dart` (+ DI registration), cubit
  `trip_privacy_export_cubit`, and a `showTripPrivacyExportSheet` bottom-sheet
  preview with a "Copia" (clipboard) action and a protected/non-protected chip.
- Export action added to the `TripDetailPage` app bar (Icons.ios_share). v1 is
  text-only: copy / simple share, no map, no file export.

Tests
- Backend `mobility/tests/test_privacy_export.py`: precise unprotected with real
  coords/label, approximate masks label + cloaks coords + no precise leak in
  text, saved preference unchanged, 404 for other users.
- Mobile `trip_privacy_export_cubit_test.dart` (service call, loading->ready
  preview state, non-precise text has no precise geometry/labels, error state)
  and `trip_privacy_export_dto_test.dart` (parsing + masked wording).

Verification: `flutter analyze` clean, full `flutter test` green (96 tests).
Backend export tests collect cleanly but were not executed (local Postgres down).
