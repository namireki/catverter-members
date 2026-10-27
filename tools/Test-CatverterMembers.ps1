[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root)
$problems = [System.Collections.Generic.List[string]]::new()
$utf8Strict = [Text.UTF8Encoding]::new($false, $true)

$migration = [ordered]@{
    repository = 'namireki/CatverterV2'
    commit = 'a028e772b3dfc81e68d588a354c74294be8479be'
    path = 'committee-repository/committee.json'
    documentVersion = '1.0.0'
    updatedAt = '2026-10-24T00:00:00Z'
    sourceLicense = 'Apache-2.0'
}

$expectedCommittee = [ordered]@{
    title = [ordered]@{
        en = 'The Committee'
        it = 'Il Comitato'
    }
    description = [ordered]@{
        en = 'The authority that translates incomprehensible human units into units that make immediate sense from a feline point of view.'
        it = "L'autorità che traduce le incomprensibili unità di misura umane in unità che abbiano senso immediato dal punto di vista felino."
    }
    statuteTitle = [ordered]@{
        en = 'Official statute'
        it = 'Statuto ufficiale'
    }
    statute = [ordered]@{
        en = 'Under M.E.O.W. Directive 9/9 (Ministry for the Evaluation of Observational Weirdness), the Committee shall ensure that every quantity can be expressed through cat-perceivable equivalents.'
        it = "Ai sensi della Direttiva M.I.A.O. 9/9 (Ministero per l'Interpretazione delle Astrazioni Osservative), il Comitato è incaricato di garantire che ogni quantità possa essere espressa mediante equivalenze gattosamente percepibili."
    }
}

$expectedMembers = @(
    [ordered]@{
        id = 'pigro'
        catName = 'Pigro'
        accentColor = '#F3B13F'
        committeePosition = [ordered]@{
            en = 'President of Applied Measurements'
            it = 'Presidente delle Misure Applicate'
        }
        shortDescription = [ordered]@{
            en = 'Calls meetings by sitting on the agenda and decides whether a unit deserves official recognition in the catverse.'
            it = "Convoca le riunioni sedendosi sull'ordine del giorno e decide se un'unità merita il riconoscimento ufficiale del catverso."
        }
    },
    [ordered]@{
        id = 'gino'
        catName = 'Gino'
        accentColor = '#EBC45C'
        committeePosition = [ordered]@{
            en = 'Inspector of Suspicious Heat'
            it = 'Ispettore del calore sospetto'
        }
        shortDescription = [ordered]@{
            en = 'Certifies that every object declared “hot” has first been tested with an official paw touch and, when required, a spectacular retreat.'
            it = 'Certifica che ogni oggetto dichiarato “caldo” sia stato preventivamente testato mediante apposito tocco con zampa ed eventuale fuga spettacolare.'
        }
    },
    [ordered]@{
        id = 'ludovico'
        catName = 'Ludovico'
        accentColor = '#BACD8A'
        committeePosition = [ordered]@{
            en = 'Supreme Reviewer of Naps'
            it = 'Revisore Supremo dei Sonnellini'
        }
        shortDescription = [ordered]@{
            en = 'Checks units of time against the only reliable clock: whether a nap was short, correct, or interrupted with appropriate cursing.'
            it = "Controlla le unità di tempo con l'unico orologio affidabile: se il sonnellino è stato breve, corretto o interrotto con maleducazione."
        }
    },
    [ordered]@{
        id = 'agata'
        catName = 'Agata'
        accentColor = '#C9ADEE'
        committeePosition = [ordered]@{
            en = 'Director of Vertical Ambition'
            it = "Direttore dell'Ambizione Verticale"
        }
        shortDescription = [ordered]@{
            en = 'Evaluates height, distance, and jumping measurements. Human declarations are corrected according to feline climbing standards.'
            it = "Valuta tutte le misure di altezza, distanza e salto. Le dichiarazioni umane vengono corrette secondo gli standard felini di arrampicabilità."
        }
    },
    [ordered]@{
        id = 'seat-five'
        catName = 'Seggio Cinque'
        accentColor = '#8CCFE5'
        committeePosition = [ordered]@{
            en = 'Officer for Air Currents'
            it = "Responsabile delle correnti d'aria"
        }
        shortDescription = [ordered]@{
            en = 'Asks to leave when the door is closed, then declines to leave. Once the door closes again, the cycle resumes.'
            it = 'Chiede di uscire quando la porta è chiusa, per poi non uscire affatto. Se la porta viene chiusa, il ciclo ricomincia.'
        }
    }
)

function Add-Problem {
    param([string]$Message)
    $script:problems.Add($Message)
}

function Get-RelativePath {
    param([string]$Path)

    $rootWithSeparator = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($rootWithSeparator.Length).Replace('\', '/')
    }
    return $fullPath.Replace('\', '/')
}

function Get-Sha256Hex {
    param([byte[]]$Bytes)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-NormalizedJsonBytes {
    param([string]$Text)

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    return [Text.Encoding]::UTF8.GetBytes($normalized)
}

function Read-StrictUtf8 {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Problem "$(Get-RelativePath $Path): file is missing"
        return $null
    }

    $bytes = [IO.File]::ReadAllBytes($Path)
    $relative = Get-RelativePath $Path
    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Add-Problem "${relative}: UTF-8 BOM is not allowed"
        return $null
    }

    try {
        $text = $utf8Strict.GetString($bytes)
    }
    catch {
        Add-Problem "${relative}: invalid UTF-8 ($($_.Exception.Message))"
        return $null
    }

    if ($text.Contains("`r")) {
        Add-Problem "${relative}: CRLF and lone CR line endings are not allowed"
    }
    return $text
}

function Visit-JsonElement {
    param(
        [System.Text.Json.JsonElement]$Element,
        [string]$Owner
    )

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $keys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $keys.Add($property.Name)) {
                Add-Problem "${Owner}: duplicate JSON property '$($property.Name)'"
            }
            Visit-JsonElement $property.Value "${Owner}.$($property.Name)"
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) {
            Visit-JsonElement $item "${Owner}[$index]"
            $index++
        }
    }
}

function Test-JsonSyntax {
    param(
        [string]$Text,
        [string]$Owner
    )

    try {
        $document = [System.Text.Json.JsonDocument]::Parse(
            $Text,
            [System.Text.Json.JsonDocumentOptions]::new())
    }
    catch {
        Add-Problem "${Owner}: invalid JSON ($($_.Exception.Message))"
        return $false
    }

    try {
        Visit-JsonElement $document.RootElement $Owner
    }
    finally {
        $document.Dispose()
    }
    return $true
}

function Read-JsonDocument {
    param([string]$Path)

    $text = Read-StrictUtf8 $Path
    if ($null -eq $text) {
        return $null
    }
    $owner = Get-RelativePath $Path
    if (-not (Test-JsonSyntax $text $owner)) {
        return $null
    }

    try {
        $value = ConvertFrom-Json -InputObject $text -AsHashtable -DateKind String
    }
    catch {
        Add-Problem "${owner}: invalid JSON ($($_.Exception.Message))"
        return $null
    }
    if ($value -isnot [System.Collections.IDictionary]) {
        Add-Problem "${owner}: root must be an object"
        return $null
    }
    return $value
}

function Test-AllowedKeys {
    param(
        [string]$Owner,
        [object]$Value,
        [string[]]$Required,
        [string[]]$Allowed
    )

    if ($Value -isnot [System.Collections.IDictionary]) {
        Add-Problem "${Owner}: must be an object"
        return
    }
    foreach ($key in $Required) {
        if (-not $Value.Contains($key)) {
            Add-Problem "${Owner}: missing required property '$key'"
        }
    }
    foreach ($key in $Value.Keys) {
        if ($key -notin $Allowed) {
            Add-Problem "${Owner}: unknown property '$key'"
        }
    }
}

function Test-ExactKeys {
    param(
        [string]$Owner,
        [object]$Value,
        [string[]]$Keys
    )
    Test-AllowedKeys $Owner $Value $Keys $Keys
}

function Test-String {
    param(
        [string]$Owner,
        [object]$Value,
        [string]$Pattern = $null
    )

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        Add-Problem "${Owner}: must be a non-empty string"
        return $false
    }
    if ($null -ne $Pattern -and $Value -notmatch $Pattern) {
        Add-Problem "${Owner}: has an invalid value"
        return $false
    }
    return $true
}

function Test-Version {
    param([string]$Owner, [object]$Value)
    [void](Test-String $Owner $Value '^[0-9]+(?:\.[0-9]+){1,3}$')
}

function Test-UtcTimestamp {
    param([string]$Owner, [object]$Value)

    if ($Value -isnot [string]) {
        Add-Problem "${Owner}: must be a canonical UTC timestamp"
        return
    }
    $text = $Value
    if ($text -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') {
        Add-Problem "${Owner}: must be a canonical UTC timestamp"
        return
    }
    [DateTimeOffset]$parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParseExact(
            $text,
            'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref]$parsed)) {
        Add-Problem "${Owner}: must be a canonical UTC timestamp"
    }
}

function Test-Date {
    param([string]$Owner, [object]$Value)

    $text = [string]$Value
    if ($Value -isnot [string] -or $text -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') {
        Add-Problem "${Owner}: must be a YYYY-MM-DD date"
        return
    }
    [DateTime]$parsed = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact(
            $text,
            'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref]$parsed)) {
        Add-Problem "${Owner}: must be a YYYY-MM-DD date"
    }
}

function Test-Localized {
    param([string]$Owner, [object]$Value)

    if ($Value -isnot [System.Collections.IDictionary] -or $Value.Count -eq 0) {
        Add-Problem "${Owner}: must be a non-empty localized object"
        return
    }
    if (-not $Value.Contains('en') -or
        $Value['en'] -isnot [string] -or
        [string]::IsNullOrWhiteSpace($Value['en'])) {
        Add-Problem "${Owner}: must contain a non-empty English 'en' value"
    }
    foreach ($language in $Value.Keys) {
        if ([string]$language -notmatch '^[a-z]{2}(?:-[A-Z][a-z0-9]{1,7})?$') {
            Add-Problem "${Owner}: invalid language code '$language'"
        }
        if ($Value[$language] -isnot [string] -or
            [string]::IsNullOrWhiteSpace($Value[$language])) {
            Add-Problem "${Owner}: translation '$language' must not be blank"
        }
    }
}

function Test-CanonicalLocalized {
    param(
        [string]$Owner,
        [object]$Actual,
        [object]$Expected
    )

    Test-Localized $Owner $Actual
    if ($Actual -isnot [System.Collections.IDictionary]) {
        return
    }
    foreach ($language in @('en', 'it')) {
        if (-not $Actual.Contains($language) -or
            [string]$Actual[$language] -cne [string]$Expected[$language]) {
            Add-Problem "${Owner}.${language}: does not match the canonical migration value"
        }
    }
}

function Test-Migration {
    param([string]$Owner, [object]$Value)

    $fields = @('repository', 'commit', 'path', 'documentVersion', 'updatedAt', 'sourceLicense')
    Test-ExactKeys $Owner $Value $fields
    if ($Value -isnot [System.Collections.IDictionary]) {
        return
    }
    foreach ($field in $fields) {
        if ([string]$Value[$field] -cne [string]$migration[$field]) {
            Add-Problem "${Owner}.${field}: exact migration provenance is required"
        }
    }
    Test-UtcTimestamp "${Owner}.updatedAt" $Value['updatedAt']
}

function Test-PatreonProvenance {
    param([string]$Owner, [object]$Value)

    Test-ExactKeys $Owner $Value @('type', 'documentVersion', 'updatedAt', 'policyPath')
    if ($Value -isnot [System.Collections.IDictionary]) {
        return
    }
    if ([string]$Value['type'] -cne 'contribution-policy') {
        Add-Problem "${Owner}.type: must be contribution-policy"
    }
    if ([string]$Value['documentVersion'] -cne '1.0.0') {
        Add-Problem "${Owner}.documentVersion: must be 1.0.0"
    }
    if ([string]$Value['policyPath'] -cne 'CONTRIBUTING.md') {
        Add-Problem "${Owner}.policyPath: must be CONTRIBUTING.md"
    }
    Test-UtcTimestamp "${Owner}.updatedAt" $Value['updatedAt']
}

function Test-Committee {
    param([string]$Owner, [object]$Value)

    $fields = @('title', 'description', 'statuteTitle', 'statute')
    Test-ExactKeys $Owner $Value $fields
    if ($Value -isnot [System.Collections.IDictionary]) {
        return
    }
    foreach ($field in $fields) {
        Test-CanonicalLocalized "${Owner}.${field}" $Value[$field] $expectedCommittee[$field]
    }
}

function Test-SchemaPropertyConst {
    param(
        [string]$Owner,
        [object]$Properties,
        [string]$Name,
        [object]$Expected
    )

    if ($Properties -isnot [System.Collections.IDictionary] -or
        -not $Properties.Contains($Name) -or
        $Properties[$Name] -isnot [System.Collections.IDictionary] -or
        $Properties[$Name]['const'] -cne $Expected) {
        Add-Problem "${Owner}.properties.${Name}: identity const is incorrect"
    }
}

function Test-SchemaIdentity {
    param(
        [string]$Path,
        [string]$ExpectedTitle,
        [string]$ExpectedId,
        [string]$ExpectedSchemaReference,
        [string[]]$ExpectedRequired,
        [string[]]$ExpectedProperties,
        [string[]]$ExpectedDefinitions,
        [bool]$CatalogSchema
    )

    $schema = Read-JsonDocument $Path
    if ($null -eq $schema) {
        return
    }
    $owner = Get-RelativePath $Path
    $topKeys = @('$schema', '$id', 'title', 'type', 'additionalProperties', 'required', 'properties', '$defs')
    if ($CatalogSchema) {
        $topKeys += 'allOf'
    }
    Test-ExactKeys $owner $schema $topKeys
    if ([string]$schema['$schema'] -cne 'https://json-schema.org/draft/2020-12/schema') {
        Add-Problem "${owner}.'$schema': must use JSON Schema draft 2020-12"
    }
    if ([string]$schema['$id'] -cne $ExpectedId) {
        Add-Problem "${owner}.'$id': public identity is incorrect"
    }
    if ([string]$schema['title'] -cne $ExpectedTitle) {
        Add-Problem "${owner}.title: schema identity is incorrect"
    }
    if ([string]$schema['type'] -cne 'object' -or $schema['additionalProperties'] -ne $false) {
        Add-Problem "${owner}: root schema must be a closed object"
    }
    $required = @($schema['required'])
    foreach ($key in $ExpectedRequired) {
        if ($key -notin $required) {
            Add-Problem "${owner}.required: missing '$key'"
        }
    }
    $properties = $schema['properties']
    if ($properties -is [System.Collections.IDictionary]) {
        foreach ($key in $ExpectedProperties) {
            if (-not $properties.Contains($key)) {
                Add-Problem "${owner}.properties: missing '$key'"
            }
        }
        foreach ($key in $properties.Keys) {
            if ($key -notin $ExpectedProperties) {
                Add-Problem "${owner}.properties: unknown '$key'"
            }
        }
        Test-SchemaPropertyConst $owner $properties '$schema' $ExpectedSchemaReference
        if ($CatalogSchema) {
            Test-SchemaPropertyConst $owner $properties 'documentType' 'catverter-member-catalog'
        }
        else {
            Test-SchemaPropertyConst $owner $properties 'documentType' 'catverter-members-manifest'
        }
        Test-SchemaPropertyConst $owner $properties 'schemaVersion' 1
    }
    else {
        Add-Problem "${owner}.properties: must be an object"
    }
    $definitions = $schema['$defs']
    if ($definitions -isnot [System.Collections.IDictionary]) {
        Add-Problem "${owner}.'$defs': must be an object"
    }
    else {
        foreach ($key in $ExpectedDefinitions) {
            if (-not $definitions.Contains($key)) {
                Add-Problem "${owner}.'$defs': missing '$key'"
            }
        }
        foreach ($key in $definitions.Keys) {
            if ($key -notin $ExpectedDefinitions) {
                Add-Problem "${owner}.'$defs': unknown '$key'"
            }
        }
    }
}

function Test-CatalogSchemaIdentity {
    param([string]$Path)

    Test-SchemaIdentity `
        $Path `
        'Catverter members catalog v1' `
        'https://raw.githubusercontent.com/namireki/catverter-members/main/schemas/catverter-members-catalog-v1.schema.json' `
        '../schemas/catverter-members-catalog-v1.schema.json' `
        @('$schema', 'documentType', 'schemaVersion', 'catalogId', 'classification', 'trust', 'version', 'updatedAt', 'provenance', 'members') `
        @('$schema', 'documentType', 'schemaVersion', 'catalogId', 'classification', 'trust', 'version', 'updatedAt', 'provenance', 'committee', 'members') `
        @('localized', 'standardProvenance', 'patreonProvenance', 'committee', 'memberId', 'photo', 'rights', 'licenseRights', 'permissionRights', 'consent', 'standardMember', 'patreonMember') `
        $true

    $schema = Read-JsonDocument $Path
    if ($null -eq $schema) {
        return
    }
    $owner = Get-RelativePath $Path
    $properties = $schema['properties']
    Test-SchemaPropertyConst $owner $properties 'documentType' 'catverter-member-catalog'
    Test-SchemaPropertyConst $owner $properties 'schemaVersion' 1

    function Test-DefinitionShape {
        param(
            [string]$Name,
            [string[]]$Required,
            [string[]]$PropertyNames,
            [bool]$HasAllOf = $false
        )

        if ($schema['$defs'] -isnot [System.Collections.IDictionary] -or
            -not $schema['$defs'].Contains($Name)) {
            return
        }
        $definition = $schema['$defs'][$Name]
        $definitionKeys = @('type', 'additionalProperties', 'required', 'properties')
        if ($HasAllOf) {
            $definitionKeys += 'allOf'
        }
        Test-ExactKeys "${owner}.'`$defs'.$Name" $definition $definitionKeys
        if ($definition['additionalProperties'] -ne $false) {
            Add-Problem "${owner}.'`$defs'.${Name}: must reject unknown properties"
        }
        foreach ($requiredName in $Required) {
            if ($requiredName -notin @($definition['required'])) {
                Add-Problem "${owner}.'`$defs'.$Name.required: missing '$requiredName'"
            }
        }
        if ($definition['properties'] -is [System.Collections.IDictionary]) {
            foreach ($propertyName in $PropertyNames) {
                if (-not $definition['properties'].Contains($propertyName)) {
                    Add-Problem "${owner}.'`$defs'.$Name.properties: missing '$propertyName'"
                }
            }
            foreach ($propertyName in $definition['properties'].Keys) {
                if ($propertyName -notin $PropertyNames) {
                    Add-Problem "${owner}.'`$defs'.$Name.properties: unknown '$propertyName'"
                }
            }
        }
    }

    Test-DefinitionShape 'standardMember' `
        @('id', 'classification', 'catName', 'committeePosition', 'shortDescription', 'accentColor') `
        @('id', 'classification', 'catName', 'committeePosition', 'shortDescription', 'accentColor', 'photo')
    Test-DefinitionShape 'patreonMember' `
        @('id', 'classification', 'catName', 'committeePosition', 'consent') `
        @('id', 'classification', 'catName', 'committeePosition', 'shortDescription', 'consent', 'photo') `
        $true
    Test-DefinitionShape 'photo' `
        @('path', 'sha256', 'byteLength', 'mediaType', 'rights') `
        @('path', 'sha256', 'byteLength', 'mediaType', 'rights')
}

function Test-MediaPrefix {
    param([byte[]]$Bytes, [byte[]]$Prefix)

    if ($Bytes.Length -lt $Prefix.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Prefix.Length; $index++) {
        if ($Bytes[$index] -ne $Prefix[$index]) {
            return $false
        }
    }
    return $true
}

function Get-AssetMediaType {
    param([byte[]]$Bytes)

    if (Test-MediaPrefix $Bytes ([byte[]](0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))) {
        return 'image/png'
    }
    if (Test-MediaPrefix $Bytes ([byte[]](0xff, 0xd8, 0xff))) {
        return 'image/jpeg'
    }
    if ($Bytes.Length -ge 12 -and
        (Test-MediaPrefix $Bytes ([byte[]](0x52, 0x49, 0x46, 0x46))) -and
        $Bytes[8] -eq 0x57 -and $Bytes[9] -eq 0x45 -and
        $Bytes[10] -eq 0x42 -and $Bytes[11] -eq 0x50) {
        return 'image/webp'
    }
    return $null
}

function Test-Rights {
    param([string]$Owner, [object]$Value)

    if ($Value -isnot [System.Collections.IDictionary]) {
        Add-Problem "${Owner}: must be a license or permission rights object"
        return
    }
    $hasLicense = $Value.Contains('license')
    $hasPermission = $Value.Contains('permissionReference')
    if ($hasLicense -and $hasPermission) {
        Add-Problem "${Owner}: must use exactly one rights basis"
        return
    }
    if ($hasLicense) {
        Test-AllowedKeys $Owner $Value `
            @('copyrightHolder', 'license', 'source') `
            @('copyrightHolder', 'license', 'source', 'attribution')
    }
    elseif ($hasPermission) {
        Test-AllowedKeys $Owner $Value `
            @('copyrightHolder', 'permissionReference') `
            @('copyrightHolder', 'permissionReference', 'source', 'attribution')
    }
    else {
        Add-Problem "${Owner}: must contain license or permissionReference"
        return
    }
    foreach ($field in $Value.Keys) {
        [void](Test-String "${Owner}.${field}" $Value[$field])
    }
}

function Test-Photo {
    param(
        [string]$Owner,
        [object]$Value,
        [string]$Classification,
        [string]$MemberId,
        [System.Collections.Generic.HashSet[string]]$PhotoReferences
    )

    if ($Value -isnot [System.Collections.IDictionary]) {
        Add-Problem "${Owner}: must be an object when present"
        return
    }
    Test-ExactKeys $Owner $Value @('path', 'sha256', 'byteLength', 'mediaType', 'rights')
    $path = [string]$Value['path']
    $pattern = '^assets/(standard-committee|patreon-members)/([a-z0-9](?:[a-z0-9-]*[a-z0-9])?)\.(jpe?g|png|webp)$'
    $match = [regex]::Match($path, $pattern)
    if (-not $match.Success -or $path.Contains('\') -or $path.Contains('..') -or $path.StartsWith('/')) {
        Add-Problem "${Owner}.path: must be a safe controlled relative asset path"
        return
    }

    $pathClass = $match.Groups[1].Value
    $pathId = $match.Groups[2].Value
    $extension = $match.Groups[3].Value
    if ($pathClass -cne $(if ($Classification -eq 'standard-committee') { 'standard-committee' } else { 'patreon-members' })) {
        Add-Problem "${Owner}.path: asset classification does not match '$Classification'"
    }
    if ($pathId -cne $MemberId) {
        Add-Problem "${Owner}.path: filename does not match member id '$MemberId'"
    }
    if (-not $PhotoReferences.Add($path)) {
        Add-Problem "${Owner}.path: duplicate photo path '$path'"
    }
    if ([string]$Value['sha256'] -notmatch '^[0-9a-f]{64}$') {
        Add-Problem "${Owner}.sha256: must be a lowercase SHA-256"
    }
    $length = 0L
    if (-not [int64]::TryParse([string]$Value['byteLength'], [ref]$length) -or $length -lt 1) {
        Add-Problem "${Owner}.byteLength: must be a positive integer"
    }
    $mediaType = [string]$Value['mediaType']
    if ($mediaType -notin @('image/jpeg', 'image/png', 'image/webp')) {
        Add-Problem "${Owner}.mediaType: GIF and unsupported media types are not allowed"
    }
    $expectedMediaType = switch ($extension) {
        'jpg' { 'image/jpeg' }
        'jpeg' { 'image/jpeg' }
        'png' { 'image/png' }
        'webp' { 'image/webp' }
    }
    if ($mediaType -cne $expectedMediaType) {
        Add-Problem "${Owner}.mediaType: does not match the path extension"
    }
    Test-Rights "${Owner}.rights" $Value['rights']

    $assetPath = Join-Path $Root ($path -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
        Add-Problem "${Owner}.path: referenced asset is missing"
        return
    }
    $bytes = [IO.File]::ReadAllBytes($assetPath)
    if ($length -ne $bytes.Length) {
        Add-Problem "${Owner}.byteLength: does not match the raw asset length"
    }
    $actualHash = Get-Sha256Hex $bytes
    if ([string]$Value['sha256'] -cne $actualHash) {
        Add-Problem "${Owner}.sha256: does not match the raw asset SHA-256"
    }
    $actualMediaType = Get-AssetMediaType $bytes
    if ($null -eq $actualMediaType) {
        Add-Problem "${Owner}: raw asset has unsupported or invalid media magic"
    }
    elseif ($mediaType -cne $actualMediaType) {
        Add-Problem "${Owner}.mediaType: does not match raw media magic"
    }
}

$manifestPath = Join-Path $Root 'members-manifest.json'
$manifestDocument = Read-JsonDocument $manifestPath
$manifestCatalogs = @()
$seenCatalogIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$memberIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$photoReferences = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$catalogDocuments = @{}

if ($null -ne $manifestDocument) {
    Test-ExactKeys 'members-manifest.json' $manifestDocument @(
        '$schema', 'documentType', 'schemaVersion', 'version', 'updatedAt',
        'repository', 'revisionPolicy',
        'jsonNormalization', 'hashAlgorithm', 'catalogSchema', 'catalogs', 'migration'
    )
    if ([string]$manifestDocument['$schema'] -cne 'schemas/catverter-members-manifest-v1.schema.json') {
        Add-Problem "members-manifest.json.'`$schema': unexpected schema reference"
    }
    if ([string]$manifestDocument['documentType'] -cne 'catverter-members-manifest') {
        Add-Problem 'members-manifest.json.documentType: unexpected value'
    }
    if ($manifestDocument['schemaVersion'] -ne 1) {
        Add-Problem 'members-manifest.json.schemaVersion: must be 1'
    }
    Test-Version 'members-manifest.json.version' $manifestDocument['version']
    Test-UtcTimestamp 'members-manifest.json.updatedAt' $manifestDocument['updatedAt']
    if ([string]$manifestDocument['repository'] -cne 'namireki/catverter-members') {
        Add-Problem 'members-manifest.json.repository: unexpected repository identity'
    }
    if ([string]$manifestDocument['revisionPolicy'] -cne 'github-main-resolved-to-commit') {
        Add-Problem 'members-manifest.json.revisionPolicy: unexpected revision policy'
    }
    if ([string]$manifestDocument['jsonNormalization'] -cne 'utf8-lf') {
        Add-Problem 'members-manifest.json.jsonNormalization: must be utf8-lf'
    }
    if ([string]$manifestDocument['hashAlgorithm'] -cne 'sha256') {
        Add-Problem 'members-manifest.json.hashAlgorithm: must be sha256'
    }
    Test-Migration 'members-manifest.json.migration' $manifestDocument['migration']

    $catalogSchema = $manifestDocument['catalogSchema']
    Test-ExactKeys 'members-manifest.json.catalogSchema' $catalogSchema @('path', 'sha256', 'mediaType')
    if ($catalogSchema -is [System.Collections.IDictionary]) {
        if ([string]$catalogSchema['path'] -cne 'schemas/catverter-members-catalog-v1.schema.json') {
            Add-Problem 'members-manifest.json.catalogSchema.path: unexpected catalog schema path'
        }
        if ([string]$catalogSchema['mediaType'] -cne 'application/schema+json') {
            Add-Problem 'members-manifest.json.catalogSchema.mediaType: must be application/schema+json'
        }
        if ([string]$catalogSchema['sha256'] -notmatch '^[0-9a-f]{64}$') {
            Add-Problem 'members-manifest.json.catalogSchema.sha256: must be a lowercase SHA-256'
        }
        else {
            $schemaPath = Join-Path $Root ($catalogSchema['path'] -replace '/', [IO.Path]::DirectorySeparatorChar)
            $schemaText = Read-StrictUtf8 $schemaPath
            if ($null -ne $schemaText) {
                $actualSchemaHash = Get-Sha256Hex (Get-NormalizedJsonBytes $schemaText)
                if ([string]$catalogSchema['sha256'] -cne $actualSchemaHash) {
                    Add-Problem 'members-manifest.json.catalogSchema.sha256: does not match the normalized catalog schema'
                }
            }
        }
    }

    if ($manifestDocument['catalogs'] -isnot [array]) {
        Add-Problem 'members-manifest.json.catalogs: must be an array'
    }
    else {
        $manifestCatalogs = @($manifestDocument['catalogs'])
    }
}

if ($manifestCatalogs.Count -ne 2) {
    Add-Problem 'members-manifest.json.catalogs: exactly two catalog pointers are required'
}

$expectedPointers = @{
    'standard-committee' = @{
        classification = 'standard-committee'
        trust = 'official'
        path = 'catalogs/standard-committee.json'
    }
    'patreon-members' = @{
        classification = 'patreon-member'
        trust = 'patreon-consented'
        path = 'catalogs/patreon-members.json'
    }
}

for ($index = 0; $index -lt $manifestCatalogs.Count; $index++) {
    $pointer = $manifestCatalogs[$index]
    $owner = "members-manifest.json.catalogs[$index]"
    Test-ExactKeys $owner $pointer @('id', 'classification', 'trust', 'path', 'sha256', 'mediaType')
    if ($pointer -isnot [System.Collections.IDictionary]) {
        continue
    }
    $catalogId = [string]$pointer['id']
    if (-not $seenCatalogIds.Add($catalogId)) {
        Add-Problem "${owner}.id: duplicate catalog id '$catalogId'"
    }
    if (-not $expectedPointers.ContainsKey($catalogId)) {
        Add-Problem "${owner}.id: unknown catalog id '$catalogId'"
        continue
    }
    $expectedPointer = $expectedPointers[$catalogId]
    foreach ($field in @('classification', 'trust', 'path')) {
        if ([string]$pointer[$field] -cne [string]$expectedPointer[$field]) {
            Add-Problem "${owner}.${field}: does not match the controlled catalog pointer"
        }
    }
    if ([string]$pointer['mediaType'] -cne 'application/json') {
        Add-Problem "${owner}.mediaType: must be application/json"
    }
    if ([string]$pointer['sha256'] -notmatch '^[0-9a-f]{64}$') {
        Add-Problem "${owner}.sha256: must be a lowercase SHA-256"
    }
    $catalogPath = Join-Path $Root ($expectedPointer.path -replace '/', [IO.Path]::DirectorySeparatorChar)
    $catalogText = Read-StrictUtf8 $catalogPath
    if ($null -ne $catalogText -and [string]$pointer['sha256'] -match '^[0-9a-f]{64}$') {
        $actualHash = Get-Sha256Hex (Get-NormalizedJsonBytes $catalogText)
        if ([string]$pointer['sha256'] -cne $actualHash) {
            Add-Problem "${owner}.sha256: does not match the normalized catalog JSON"
        }
    }
    $catalog = Read-JsonDocument $catalogPath
    if ($null -eq $catalog) {
        continue
    }
    $catalogDocuments[$catalogId] = $catalog
    $catalogOwner = $expectedPointer.path
    if ($catalogId -eq 'standard-committee') {
        Test-ExactKeys $catalogOwner $catalog @(
            '$schema', 'documentType', 'schemaVersion', 'catalogId',
            'classification', 'trust', 'version', 'updatedAt', 'provenance',
            'committee', 'members'
        )
    }
    else {
        Test-ExactKeys $catalogOwner $catalog @(
            '$schema', 'documentType', 'schemaVersion', 'catalogId',
            'classification', 'trust', 'version', 'updatedAt', 'provenance',
            'members'
        )
    }
    if ([string]$catalog['$schema'] -cne '../schemas/catverter-members-catalog-v1.schema.json') {
        Add-Problem "${catalogOwner}.'`$schema': unexpected schema reference"
    }
    if ([string]$catalog['documentType'] -cne 'catverter-member-catalog') {
        Add-Problem "${catalogOwner}.documentType: unexpected value"
    }
    if ($catalog['schemaVersion'] -ne 1) {
        Add-Problem "${catalogOwner}.schemaVersion: must be 1"
    }
    if ([string]$catalog['catalogId'] -cne $catalogId) {
        Add-Problem "${catalogOwner}.catalogId: does not match manifest pointer"
    }
    if ([string]$catalog['classification'] -cne [string]$expectedPointer.classification) {
        Add-Problem "${catalogOwner}.classification: does not match manifest pointer"
    }
    if ([string]$catalog['trust'] -cne [string]$expectedPointer.trust) {
        Add-Problem "${catalogOwner}.trust: does not match manifest pointer"
    }
    Test-Version "${catalogOwner}.version" $catalog['version']
    Test-UtcTimestamp "${catalogOwner}.updatedAt" $catalog['updatedAt']
    if ($catalogId -eq 'standard-committee') {
        Test-Migration "${catalogOwner}.provenance" $catalog['provenance']
        Test-Committee "${catalogOwner}.committee" $catalog['committee']
    }
    else {
        Test-PatreonProvenance "${catalogOwner}.provenance" $catalog['provenance']
    }

    if ($catalog['members'] -isnot [array]) {
        Add-Problem "${catalogOwner}.members: must be an array"
        continue
    }
    $members = @($catalog['members'])
    if ($catalogId -eq 'standard-committee' -and $members.Count -ne $expectedMembers.Count) {
        Add-Problem "${catalogOwner}.members: exactly the five canonical standard members are required"
    }
    for ($memberIndex = 0; $memberIndex -lt $members.Count; $memberIndex++) {
        $member = $members[$memberIndex]
        $owner = "${catalogOwner}.members[$memberIndex]"
        $isStandard = $catalogId -eq 'standard-committee'
        if ($isStandard) {
            Test-AllowedKeys $owner $member `
                @('id', 'classification', 'catName', 'committeePosition', 'shortDescription', 'accentColor') `
                @('id', 'classification', 'catName', 'committeePosition', 'shortDescription', 'accentColor', 'photo')
        }
        else {
            Test-AllowedKeys $owner $member `
                @('id', 'classification', 'catName', 'committeePosition', 'consent') `
                @('id', 'classification', 'catName', 'committeePosition', 'shortDescription', 'consent', 'photo')
        }
        if ($member -isnot [System.Collections.IDictionary]) {
            continue
        }
        $memberId = [string]$member['id']
        if ($memberId -notmatch '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$') {
            Add-Problem "${owner}.id: must use canonical lowercase stable ID syntax"
        }
        elseif (-not $memberIds.Add($memberId)) {
            Add-Problem "${owner}.id: duplicate stable ID across catalogs '$memberId'"
        }
        $expectedClassification = if ($isStandard) { 'standard-committee' } else { 'patreon-member' }
        if ([string]$member['classification'] -cne $expectedClassification) {
            Add-Problem "${owner}.classification: does not match catalog classification"
        }
        [void](Test-String "${owner}.catName" $member['catName'])
        Test-Localized "${owner}.committeePosition" $member['committeePosition']
        if ($isStandard) {
            Test-Localized "${owner}.shortDescription" $member['shortDescription']
            if ([string]$member['accentColor'] -notmatch '^#[0-9A-F]{6}$') {
                Add-Problem "${owner}.accentColor: must use uppercase #RRGGBB notation"
            }
            if ($member.Contains('photo')) {
                Test-Photo "${owner}.photo" $member['photo'] $expectedClassification $memberId $photoReferences
            }
            if ($memberIndex -lt $expectedMembers.Count) {
                $expected = $expectedMembers[$memberIndex]
                foreach ($field in @('id', 'catName', 'accentColor')) {
                    if ([string]$member[$field] -cne [string]$expected[$field]) {
                        Add-Problem "${owner}.${field}: does not match the canonical supplied member"
                    }
                }
                Test-CanonicalLocalized "${owner}.committeePosition" $member['committeePosition'] $expected.committeePosition
                Test-CanonicalLocalized "${owner}.shortDescription" $member['shortDescription'] $expected.shortDescription
            }
        }
        else {
            if ($member.Contains('shortDescription')) {
                Test-Localized "${owner}.shortDescription" $member['shortDescription']
            }
            $consent = $member['consent']
            Test-ExactKeys "${owner}.consent" $consent @('publicDisplay', 'photoDisplay', 'consentDate')
            if ($consent -is [System.Collections.IDictionary]) {
                if ($consent['publicDisplay'] -ne $true) {
                    Add-Problem "${owner}.consent.publicDisplay: must be true"
                }
                if ($consent['photoDisplay'] -isnot [bool]) {
                    Add-Problem "${owner}.consent.photoDisplay: must be boolean"
                }
                Test-Date "${owner}.consent.consentDate" $consent['consentDate']
                if ($consent['photoDisplay'] -eq $true) {
                    if (-not $member.Contains('photo')) {
                        Add-Problem "${owner}.photo: is required when consent.photoDisplay is true"
                    }
                }
                elseif ($member.Contains('photo')) {
                    Add-Problem "${owner}.photo: must be omitted when consent.photoDisplay is false"
                }
            }
            if ($member.Contains('photo')) {
                Test-Photo "${owner}.photo" $member['photo'] $expectedClassification $memberId $photoReferences
            }
        }
    }
}

foreach ($expectedCatalogId in $expectedPointers.Keys) {
    if (-not $seenCatalogIds.Contains($expectedCatalogId)) {
        Add-Problem "members-manifest.json.catalogs: missing '$expectedCatalogId' catalog"
    }
}

Test-SchemaIdentity `
    (Join-Path $Root 'schemas/catverter-members-manifest-v1.schema.json') `
    'Catverter members manifest v1' `
    'https://raw.githubusercontent.com/namireki/catverter-members/main/schemas/catverter-members-manifest-v1.schema.json' `
    'schemas/catverter-members-manifest-v1.schema.json' `
    @('$schema', 'documentType', 'schemaVersion', 'version', 'updatedAt', 'repository', 'revisionPolicy', 'jsonNormalization', 'hashAlgorithm', 'catalogSchema', 'catalogs', 'migration') `
    @('$schema', 'documentType', 'schemaVersion', 'version', 'updatedAt', 'repository', 'revisionPolicy', 'jsonNormalization', 'hashAlgorithm', 'catalogSchema', 'catalogs', 'migration') `
    @('catalogPointer', 'migration') `
    $false

Test-CatalogSchemaIdentity (Join-Path $Root 'schemas/catverter-members-catalog-v1.schema.json')

foreach ($retiredPath in @(
        'committee.json',
        'schemas/catverter-committee-v1.schema.json',
        'schemas/members-manifest.schema.json',
        'schemas/member-catalog.schema.json',
        'tools/Test-Committee.ps1',
        'tools/Test-Members.ps1',
        'tools/Test-Members.Regression.ps1',
        'tools/Update-Hashes.ps1'
    )) {
    $fullRetiredPath = Join-Path $Root ($retiredPath -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (Test-Path -LiteralPath $fullRetiredPath) {
        Add-Problem "${retiredPath}: retired legacy file must not be present"
    }
}

$assetsRoot = Join-Path $Root 'assets'
$assetPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
if (Test-Path -LiteralPath $assetsRoot -PathType Container) {
    foreach ($assetFile in @(Get-ChildItem -LiteralPath $assetsRoot -Recurse -File)) {
        $assetPath = Get-RelativePath $assetFile.FullName
        [void]$assetPaths.Add($assetPath)
        if ($assetPath -notmatch '^assets/(standard-committee|patreon-members)/[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.(?:jpe?g|png|webp)$') {
            Add-Problem "${assetPath}: asset filename is not controlled"
        }
        if (-not $photoReferences.Contains($assetPath)) {
            Add-Problem "${assetPath}: orphan asset is not referenced by a member"
        }
    }
}
foreach ($photoReference in $photoReferences) {
    if (-not $assetPaths.Contains($photoReference)) {
        Add-Problem "${photoReference}: referenced asset is not present in the repository"
    }
}

if ($problems.Count -gt 0) {
    [Console]::Error.WriteLine("Catverter members repository has $($problems.Count) problem(s):")
    foreach ($problem in $problems) {
        [Console]::Error.WriteLine("- $problem")
    }
    exit 1
}

Write-Host 'Catverter members repository is valid.'
exit 0
