# Contributing

## Contract and workflow

1. Keep all public paths exact. Do not restore retired committee schemas,
   catalogs, or tools.
2. Keep JSON UTF-8 without a BOM and LF-only. The repository `.editorconfig`
   and `.gitattributes` enforce those defaults.
3. Keep IDs lowercase and globally unique across both catalogs. A
   `patreon-member` ID must never replace or shadow a
   `standard-committee` ID.
4. Use only the exact catalog/member classification and trust pairs:
   `standard-committee`/`official` and
   `patreon-member`/`patreon-consented`.
5. Preserve English in every localized value. Italian is welcome but is not
   required for a new entry.
6. Run `tools/Update-ManifestHashes.ps1` after every semantic schema or
   catalog change, then run the validator and regression tests.

## Adding a Patreon member

The issue form is only a review request; it never publishes an entry
automatically. A maintainer assigns a globally unique ID and adds a member
with:

- `id`, `classification`, `catName`, and localized `committeePosition`;
- optional localized `shortDescription`;
- `consent.publicDisplay: true`, a boolean `photoDisplay`, and a
  `consentDate` in `YYYY-MM-DD` form;
- a photo only when `photoDisplay` is true; and
- complete license- or permission-basis rights for that photo.

Do not include private contact details, identity documents, payment data, or
other sensitive evidence in an issue or pull request. The public catalog
needs only the data and rights metadata described by the schema.

## Updating or removing a Patreon member

For an update, keep the same ID, re-check public consent, update the catalog
version and timestamp, and recalculate all manifest hashes. For a removal or
withdrawal, remove the member from the catalog, remove every active reference
to the member's photo, delete the photo file when it is no longer referenced,
and publish the resulting manifest/catalog snapshot. Never leave an orphan
asset or a stale reference in a consumer cache.

When Patreon membership ends, treat it as a catalog removal unless the member
and maintainers explicitly approve another public classification in a future
schema. The current v1 contract has no inactive Patreon state: remove the
record and asset references, then publish a new pinned snapshot.

## Photo handling

Use only `assets/standard-committee/{id}.jpg|jpeg|png|webp` or
`assets/patreon-members/{id}.jpg|jpeg|png|webp`. Record exact raw byte length,
lowercase SHA-256, media type, and one rights basis. The validator checks
extension, MIME, magic bytes, path/classification, member ID, duplicate
references, and orphan assets.

## Commands

```powershell
pwsh -NoProfile -File ./tools/Update-ManifestHashes.ps1
pwsh -NoProfile -File ./tools/Test-CatverterMembers.ps1
pwsh -NoProfile -File ./tests/Test-Validator.ps1
pwsh -NoProfile -File ./tools/Update-ManifestHashes.ps1 -Check
```

The updater only computes normalized hashes for the catalog schema and both
catalogs. It does not fetch remote data or store evidence.
