# Contributing member updates

Repository-authored text and templates are Copyright 2026 Namireki Studio and
licensed under Apache-2.0.

## Add or update a Patreon member

1. Copy `templates/patreon-member.template.json` into the `members` array in
   `catalogs/patreon-members.json`. For a premium member, use
   `templates/premium-patreon-member.template.json` instead.
2. Replace the example with the member's real data. IDs use lowercase ASCII
   words separated by single hyphens, are globally unique across both
   catalogs, and are never reassigned after removal.
3. Keep `memberType` equal to `patreon`. English is required in every localized
   field; additional keys must be canonical BCP 47 language tags.
4. Remove `description` when none was supplied. Do not publish invented text.
5. Omit `premiumSortOrder` for a default Patreon member. For a premium member,
   set it to a canonical JSON integer from `0` through `2147483647`, written
   as `0` or a non-zero digit followed by digits. Negative values, fractions,
   decimal or exponent spellings such as `1.0` or `1e0`, strings, booleans,
   null, and values above `2147483647` are rejected.
6. Keep `photo` equal to `null` unless all photo requirements below are met.
7. Increment the Patreon catalog's three-component `version` and set
   `updatedAt` to a real UTC timestamp in `YYYY-MM-DDTHH:mm:ssZ` form.
8. Run `npm run update-hashes` and `npm run check`.

Patreon entries are additive. They cannot modify, shadow, or replace a standard
committee member. Standard committee changes require maintainer approval and
must keep the deprecated `committee.json` projection synchronized.

Consumers show premium members with a gold star. They group premium members by
ascending `premiumSortOrder`, place every premium group before members without
the field, deterministically randomize ties within each premium order, and keep
default Patreon members in their randomized order.

## Add or replace a photo

Before checking in a photo, obtain the submitting human's consent and either:

- record an explicit SPDX-style license identifier; or
- copy `templates/photo-permission.template.md` to
  `permissions/<member-id>.md`, complete it without personal contact
  information, and retain the rights holder's documented approval.

Then:

1. Save the image as `assets/photos/<member-id>.png`, `.jpg`, `.jpeg`, or
   `.webp`. The maximum size is 5 MiB.
2. Set the matching media type (`image/png`, `image/jpeg`, or `image/webp`).
3. Record the raw file byte length and lowercase SHA-256 digest.
4. Set `memberConsent` to `true`.
5. For an explicitly licensed image, set `basis` to `license`, set `license`,
   and keep both permission fields `null`.
6. For documented permission, set `basis` to `documented-permission`, keep
   `license` null, set `permissionPath`, and hash the permission file as UTF-8
   after normalizing line endings to LF.
7. Run `npm run update-hashes` and `npm run check`.

External image URLs, absolute paths, path traversal, mismatched file names,
incorrect hashes or lengths, unsupported magic bytes, missing consent, and
unreferenced files are rejected.

## Remove a member or photo

Removal and replacement must be atomic in one pull request:

1. Remove or update the catalog entry.
2. Delete the old photo and any permission record that is no longer referenced.
3. Increment the affected catalog version and update its timestamp.
4. Run `npm run update-hashes` and `npm run check`.

The validator rejects orphaned files so removed photos cannot remain available
through stale catalog references. Consumers cache only complete revision-pinned
snapshots and therefore retain either the previous valid entry or the complete
new state, never a partial update.

To request an urgent removal, open a repository issue or contact the
maintainers. Identify the stable member ID and the photo path, but do not post
private contact information or sensitive consent evidence publicly.
