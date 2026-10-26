# Catverter Committee roster

Publish `committee.json` at the root of
[`namireki/catverter-members`](https://github.com/namireki/catverter-members).
Catverter reads it from:

```text
https://raw.githubusercontent.com/namireki/catverter-members/main/committee.json
```

The app validates `documentType`, `schemaVersion`, the dotted `version`, the
ISO-8601 `updatedAt` value, unique member IDs, localized text, colors, and image
URLs before accepting an update. English (`en`) is required in every localized
field; additional language codes are optional.

The root document must retain its `$schema` reference to
`schemas/catverter-committee-v1.schema.json`. Catverter rejects documents that
do not declare their public schema version.

Pull requests and pushes to `main` run the Catverter content validator. For a
local check from a sibling Catverter checkout:

```text
dotnet run --project ../CatverterV2/tools/Catverter.ContentTool -- validate-committee-repository .
```

To add portraits, place image files in an `images` directory and set a member's
`imageUrl`, for example:

```json
"imageUrl": "https://raw.githubusercontent.com/namireki/catverter-members/main/images/pigro.jpg"
```

Use HTTPS URLs. Set `imageUrl` to `null` until the image exists; Catverter will
show the member's initials instead. Increase `version` and update `updatedAt`
whenever the roster changes.
