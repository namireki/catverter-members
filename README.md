# Catverter members catalogs

This repository publishes the versioned member data consumed by Catverter.
The public entry point is [`members-manifest.json`](members-manifest.json).
The retired committee contract and every retired schema/tool name are
intentionally absent.

The manifest identifies `namireki/catverter-members` as its repository and
declares `github-main-resolved-to-commit` as its revision policy. Consumers
must reject a manifest with a different repository or revision policy.

## Exact public contract

The public files are:

- `schemas/catverter-members-manifest-v1.schema.json`
- `schemas/catverter-members-catalog-v1.schema.json`
- `catalogs/standard-committee.json`
- `catalogs/patreon-members.json`
- `tools/Test-CatverterMembers.ps1`
- `tools/Update-ManifestHashes.ps1`
- `tests/Test-Validator.ps1`

The `standard-committee` catalog and each of its members use
`classification: "standard-committee"` and `trust: "official"`. The
`patreon-members` catalog and future consented members use
`classification: "patreon-member"` and `trust: "patreon-consented"`.
Members repeat their classification; member records do not repeat trust.
Stable IDs are lowercase and globally unique, so a Patreon entry can never
shadow a committee entry.

Catalog JSON is UTF-8 without a BOM and LF-only. JSON objects have no unknown
keys and duplicate keys are rejected. The manifest declares
`jsonNormalization: "utf8-lf"` and `hashAlgorithm: "sha256"`. Catalog-schema
and catalog hashes are lowercase SHA-256 values over normalized JSON bytes:
CRLF and lone CR are converted to LF, then UTF-8 without a BOM is hashed.
Photo hashes use the exact raw image bytes.

The standard catalog preserves the five supplied member records losslessly in
`catName`, `committeePosition`, and `shortDescription`. English is required
for localized text; Italian and other valid language values are optional.
Photos, when present, use only
`assets/standard-committee/{id}.jpg|jpeg|png|webp` or
`assets/patreon-members/{id}.jpg|jpeg|png|webp`. GIF is not supported.

## Pinned snapshot API

Consumers must resolve the branch to a 40-character lowercase commit identity
before reading any data:

```text
GET https://api.github.com/repos/namireki/catverter-members/commits/main
```

Require the returned `sha` to match `^[0-9a-f]{40}$`. For one resolved
`{sha}`, fetch every item from the same raw commit URL:

```text
https://raw.githubusercontent.com/namireki/catverter-members/{sha}/members-manifest.json
https://raw.githubusercontent.com/namireki/catverter-members/{sha}/schemas/catverter-members-manifest-v1.schema.json
https://raw.githubusercontent.com/namireki/catverter-members/{sha}/schemas/catverter-members-catalog-v1.schema.json
https://raw.githubusercontent.com/namireki/catverter-members/{sha}/catalogs/standard-committee.json
https://raw.githubusercontent.com/namireki/catverter-members/{sha}/catalogs/patreon-members.json
```

Resolve photo paths from the same base URL and the exact path in the catalog.
Do not mix branch URLs, different commits, or cached files from another
snapshot. Validate strict encoding and JSON syntax, schema identity,
provenance, catalog hashes, global IDs, classification/trust, consent,
rights, photo extension/MIME/magic, raw length/hash, and orphan/reference
integrity before activation.

Stage the complete snapshot in a new cache location, validate it, and switch
the active pointer atomically. If downloading, validation, or activation
fails, retain the last known-good snapshot and use the bundled
`standard-committee` fallback. Never partially activate a catalog.

After a complete snapshot validates, list and show every Patreon entry
automatically. Use the explicit `classification` and `trust` values to render
Patreon members as visibly distinct from the official committee; never derive
that distinction from a file path, position, name, description, or color.
The migrated official catalog has no photos, so consumers must retain the
existing initials fallback for all five standard members.

## Privacy, licensing, and removal

Only publish a Patreon member after explicit `publicDisplay: true` consent.
Record only the public cat name, committee position, optional public
description/photo, consent date, and the rights metadata needed to distribute
the supplied image. Do not put private contact details, identity documents,
payment data, or sensitive evidence in this repository or an issue.

Every image must have either a license basis
(`copyrightHolder`, `license`, `source`, optional `attribution`) or a
permission basis (`copyrightHolder`, `permissionReference`, optional
`source`/`attribution`). A withdrawal or removal request is handled promptly:
remove the member record, delete active references, delete the photo asset
when no longer referenced, update the manifest hashes, and publish a new
commit. Consumers should honor the newest valid pinned snapshot and remove
the withdrawn record from active caches.

## Local validation

Run the exact public tools with PowerShell 7:

```powershell
pwsh -NoProfile -File ./tools/Update-ManifestHashes.ps1
pwsh -NoProfile -File ./tools/Test-CatverterMembers.ps1
pwsh -NoProfile -File ./tests/Test-Validator.ps1
pwsh -NoProfile -File ./tools/Update-ManifestHashes.ps1 -Check
git diff --check
```

After any semantic catalog or schema change, run the updater before
validation. Pull requests and pushes to `main` run the validator and
regression tests in GitHub Actions.

## Migration provenance

The committee catalog and manifest migration block use this exact provenance:

- repository: `namireki/CatverterV2`
- commit: `a028e772b3dfc81e68d588a354c74294be8479be`
- path: `committee-repository/committee.json`
- documentVersion: `1.0.0`
- updatedAt: `2026-10-24T00:00:00Z`
- sourceLicense: `Apache-2.0`

The Patreon root contains contribution-policy provenance only; it has no
committee or CatverterV2 source block and starts with an empty `members`
array.
