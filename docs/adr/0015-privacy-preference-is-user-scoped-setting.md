# Privacy Preference Is A User-Scoped Setting

## Status

Accepted

## Context

The project needs a user-selectable privacy level for the mobile app. The first
implementation only stores and edits the user's choice; it does not yet apply
privacy transformations to Viaggi, exports, maps, or diary segments.

The choice can change over time and is global for the user. It is not a property
of one Viaggio in this iteration.

## Decision

Store the Preferenza Privacy in a dedicated `UserPrivacySettings` model with a
one-to-one relationship to the authenticated user.

Expose it through a dedicated API:

- `GET /api/privacy/settings`
- `PUT /api/privacy/settings`

Supported Livelli Privacy are:

- `precise`
- `approximate`
- `aggregated`

## Alternatives Considered

- Add a field directly to Django's user model.
- Store a privacy level snapshot on each Viaggio.
- Keep the choice only in local mobile storage.

## Consequences

The setting is clearly separated from authentication data and can grow with
future privacy options. The mobile app can fetch and update the setting without
changing trip ingestion or diary endpoints.

Older Viaggi are not affected by changing this setting yet. Future work may add
trip snapshots, export snapshots, or privacy-aware read models if the product
needs those semantics.
