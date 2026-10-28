# Catverter member catalogs

This repository is the canonical publication point for Catverter's two member
catalogs:

| Catalog | Path | Trust | Current entries |
|---|---|---|---:|
| Standard committee | `catalogs/standard-committee.json` | Maintainer-curated, authoritative | 5 |
| Patreon members | `catalogs/patreon-members.json` | Member-submitted, additive only | 0 |

`catalog.json` is the root manifest. It advertises the exact catalog and schema
paths, normalized catalog hashes, and the raw-content URL template. The
catalogs, schemas, validator, templates, and repository-authored documentation
are Copyright 2026 Namireki Studio and licensed under Apache-2.0.

## Consumer contract

Applications must never treat mutable `main` content as a coherent snapshot.
Use this sequence:

1. Resolve `main` with
   `https://api.github.com/repos/namireki/catverter-members/commits/main` and
   retain the returned 40-character commit SHA.
2. Fetch the manifest from
   `https://raw.githubusercontent.com/namireki/catverter-members/{sha}/catalog.json`.
3. Require the manifest identity, schema version, repository, `main` ref,
   content-base template, hash algorithm, and text-hash encoding defined by
   `schemas/catverter-member-catalog-manifest-v1.schema.json`.
4. Fetch both catalog paths and schemas from the same `{sha}`. Never combine
   files from different revisions.
5. Decode catalog JSON as strict UTF-8, normalize `CRLF` and lone `CR` to `LF`,
   hash those UTF-8 bytes with SHA-256, and verify both the digest and normalized
   byte length from the manifest before parsing.
6. Validate closed object shapes, document identity, dotted versions,
   timestamps, localized text, explicit catalog/member classification, and
   globally unique IDs. If present on a Patreon member, `premiumSortOrder` must
   be a canonical JSON integer token in the inclusive range `0..2147483647`.
   A Patreon ID that matches a standard ID invalidates the snapshot; Patreon
   data can never replace an official member.
7. Resolve photo paths against
   `https://raw.githubusercontent.com/namireki/catverter-members/{sha}/`, then
   verify the raw-byte SHA-256, byte length, declared media type, magic bytes,
   consent, and rights metadata before display.
8. Commit the two catalogs and their assets to cache atomically only after the
   entire snapshot validates. Keep the previous valid snapshot on any failure.

The standard committee must also ship as a bundled application fallback. If no
valid remote or cached snapshot exists, show that bundled standard committee
without remote Patreon members. Valid Patreon entries are displayed
automatically and must be visually distinguishable using the explicit
`memberType: "patreon"` classification, not a path, position, or display name.

Consumers classify a Patreon member as premium only when
`premiumSortOrder` is present. Premium members display a gold star and are
grouped by ascending `premiumSortOrder`; every premium group appears before
members without the field. Consumers deterministically randomize members
sharing the same order among themselves. Patreon members without the field
remain in the consumer's randomized default order.

The mutable human-readable discovery URLs are:

```text
https://raw.githubusercontent.com/namireki/catverter-members/main/catalog.json
https://raw.githubusercontent.com/namireki/catverter-members/main/catalogs/standard-committee.json
https://raw.githubusercontent.com/namireki/catverter-members/main/catalogs/patreon-members.json
```

Production consumers replace `main` with the resolved commit SHA.

## Standard committee migration

The standard catalog is a lossless migration of
`namireki/CatverterV2@a028e772b3dfc81e68d588a354c74294be8479be`,
`committee-repository/committee.json`. It preserves version `1.0.0`, timestamp
`2026-10-24T00:00:00Z`, all localized committee metadata, and these five
members: `pigro`, `gino`, `ludovico`, `agata`, and `seat-five`.

`committee.json` and `schemas/catverter-committee-v1.schema.json` remain as a
deprecated compatibility projection for older Catverter builds. The validator
requires the legacy file to exactly mirror the standard catalog's ordered
metadata and members, with `imageUrl: null`; it is not a second canonical
source and must not be edited independently.

## Patreon member shape

Every Patreon member has:

- a permanent globally unique lowercase ASCII `id`;
- `memberType: "patreon"`;
- an optional `premiumSortOrder` canonical JSON integer from `0` through
  `2147483647`, whose presence marks the member as premium;
- a `catName`;
- a localized committee `position` with non-empty English;
- an optional localized short `description` of at most 280 characters; and
- an explicit `photo`, either `null` or repository-hosted integrity metadata.

The JSON Schema enforces the integer value and range. The dependency-free
repository validator additionally enforces the source token spelling
`0|[1-9][0-9]*`, so decimal and exponent spellings such as `1.0` and `1e0`
are rejected even though they represent integral JSON numbers.

The catalog is intentionally empty until real members submit entries. Do not
invent placeholder members. Copy `templates/patreon-member.template.json` for
a default member or `templates/premium-patreon-member.template.json` for a
premium member, then follow [CONTRIBUTING.md](CONTRIBUTING.md).

### Test-only Patreon UI fixture

`test/fixtures/patreon-members-20.json` contains exactly 20 invented Patreon
member records for Catverter UI and regression testing. It is test-only data,
is not a canonical catalog, is not referenced by `catalog.json`, and must never
be included in a public consumer snapshot. The regression suite injects its
records into a temporary copy of `catalogs/patreon-members.json` and runs the
real repository validator; the canonical Patreon catalog remains empty until
real consented members exist.

The fixture's premium examples are `test-patreon-pip` and
`test-patreon-pixel` at order `0`, plus
`test-patreon-maximum-whiskers` at order `10`. The shared order exercises
tie randomization, while order `10` exercises a later premium tier.

## Validation

Node.js 20 or newer is required. The validator has no runtime dependencies.

```text
npm run update-hashes
npm run check
```

`npm run check` validates the catalogs, schemas, manifest hashes, global IDs,
legacy projection, photo bytes, consent/rights records, orphaned files, and
templates, then runs the negative and positive test suite, including validation
of all 20 injected test-only Patreon records. Pull requests and pushes to `main`
run the same command in GitHub Actions. The historical
`pwsh -NoProfile -File tools/Test-Committee.ps1` command remains as a wrapper
around the canonical Node validator.

## Licensing

See [LICENSE](LICENSE) and [NOTICE](NOTICE). Member photos are not covered by
the repository's Apache-2.0 license unless the photo entry explicitly declares
that license. Every photo requires both member consent and either an explicit
license or a hash-bound repository permission record.
