import { createHash } from 'node:crypto';
import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync
} from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const VERSION_PATTERN = /^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$/;
const TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const HASH_PATTERN = /^[0-9a-f]{64}$/;
const COLOR_PATTERN = /^#[0-9A-F]{6}$/;
const PHOTO_PATH_PATTERN =
  /^assets\/photos\/[a-z0-9]+(?:-[a-z0-9]+)*\.(?:png|jpe?g|webp)$/;
const PERMISSION_PATH_PATTERN =
  /^permissions\/[a-z0-9]+(?:-[a-z0-9]+)*\.md$/;
const SPDX_PATTERN = /^[A-Za-z0-9][A-Za-z0-9.+-]*$/;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const COPYRIGHT = 'Copyright 2026 Namireki Studio';
const LICENSE = 'Apache-2.0';

const MANIFEST_PATH = 'catalog.json';
const STANDARD_PATH = 'catalogs/standard-committee.json';
const PATREON_PATH = 'catalogs/patreon-members.json';
const LEGACY_PATH = 'committee.json';

const EXPECTED_CATALOGS = [
  {
    catalogType: 'standard-committee',
    path: STANDARD_PATH,
    schemaPath: 'schemas/catverter-standard-committee-v1.schema.json'
  },
  {
    catalogType: 'patreon',
    path: PATREON_PATH,
    schemaPath: 'schemas/catverter-patreon-members-v1.schema.json'
  }
];

const REQUIRED_SCHEMAS = [
  'schemas/catverter-member-catalog-manifest-v1.schema.json',
  'schemas/catverter-standard-committee-v1.schema.json',
  'schemas/catverter-patreon-members-v1.schema.json',
  'schemas/catverter-committee-v1.schema.json'
];

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function normalizeLf(value) {
  return value.replace(/\r\n?/g, '\n');
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function displayPath(root, absolutePath) {
  return path.relative(root, absolutePath).split(path.sep).join('/');
}

function exactKeys(value, required, optional, owner, errors) {
  if (!isObject(value)) {
    errors.push(`${owner}: must be an object`);
    return false;
  }

  const allowed = new Set([...required, ...optional]);
  for (const key of required) {
    if (!Object.hasOwn(value, key)) {
      errors.push(`${owner}: missing required property '${key}'`);
    }
  }
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      errors.push(`${owner}: unknown property '${key}'`);
    }
  }
  return true;
}

function validateNfc(value, owner, errors) {
  if (typeof value === 'string') {
    if (value.normalize('NFC') !== value) {
      errors.push(`${owner}: strings must use Unicode NFC normalization`);
    }
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => validateNfc(item, `${owner}[${index}]`, errors));
    return;
  }
  if (isObject(value)) {
    for (const [key, item] of Object.entries(value)) {
      validateNfc(key, `${owner} property name`, errors);
      validateNfc(item, `${owner}.${key}`, errors);
    }
  }
}

function readUtf8(root, relativePath, errors) {
  const absolutePath = path.join(root, ...relativePath.split('/'));
  if (!existsSync(absolutePath)) {
    errors.push(`${relativePath}: file does not exist`);
    return null;
  }
  const fileInfo = lstatSync(absolutePath);
  if (fileInfo.isSymbolicLink() || !fileInfo.isFile()) {
    errors.push(`${relativePath}: must be a regular repository file, not a symlink`);
    return null;
  }

  const buffer = readFileSync(absolutePath);
  if (buffer.length >= 3 &&
      buffer[0] === 0xef &&
      buffer[1] === 0xbb &&
      buffer[2] === 0xbf) {
    errors.push(`${relativePath}: UTF-8 BOM is not allowed`);
    return null;
  }

  try {
    const text = new TextDecoder('utf-8', { fatal: true }).decode(buffer);
    if (text.includes('\0')) {
      errors.push(`${relativePath}: NUL bytes are not allowed`);
      return null;
    }
    return {
      absolutePath,
      buffer,
      text,
      normalizedText: normalizeLf(text)
    };
  } catch {
    errors.push(`${relativePath}: must be strict UTF-8`);
    return null;
  }
}

function readJson(root, relativePath, errors) {
  const file = readUtf8(root, relativePath, errors);
  if (file === null) {
    return null;
  }

  try {
    const value = JSON.parse(file.text);
    if (!isObject(value)) {
      errors.push(`${relativePath}: root must be an object`);
      return null;
    }
    validateNfc(value, relativePath, errors);
    return { ...file, value };
  } catch (error) {
    errors.push(`${relativePath}: invalid JSON (${error.message})`);
    return null;
  }
}

function validateVersion(value, owner, errors) {
  if (typeof value !== 'string' || !VERSION_PATTERN.test(value)) {
    errors.push(`${owner}: must be a three-component dotted version`);
  }
}

function validateTimestamp(value, owner, errors) {
  if (typeof value !== 'string' || !TIMESTAMP_PATTERN.test(value)) {
    errors.push(`${owner}: must be an ISO-8601 UTC timestamp at second precision`);
    return;
  }
  const parsed = Date.parse(value);
  const canonical = Number.isNaN(parsed)
    ? null
    : new Date(parsed).toISOString().replace('.000Z', 'Z');
  if (canonical !== value) {
    errors.push(`${owner}: must be a real canonical ISO-8601 UTC timestamp`);
  }
}

function validateLocalized(value, owner, errors, maximumLength) {
  if (!isObject(value) || Array.isArray(value)) {
    errors.push(`${owner}: must be a localized object`);
    return;
  }

  const keys = Object.keys(value);
  if (keys.length === 0) {
    errors.push(`${owner}: must not be empty`);
  }
  if (!Object.hasOwn(value, 'en')) {
    errors.push(`${owner}: must contain English ('en')`);
  }

  const canonicalTags = new Set();
  for (const [language, text] of Object.entries(value)) {
    let canonical;
    try {
      [canonical] = Intl.getCanonicalLocales(language);
    } catch {
      errors.push(`${owner}: '${language}' is not a valid language tag`);
      continue;
    }
    if (canonical !== language) {
      errors.push(`${owner}: language tag '${language}' must be canonical '${canonical}'`);
    }
    if (canonicalTags.has(canonical)) {
      errors.push(`${owner}: duplicate canonical language tag '${canonical}'`);
    }
    canonicalTags.add(canonical);

    if (typeof text !== 'string' || text.trim().length === 0) {
      errors.push(`${owner}.${language}: must be a non-empty string`);
    } else if (maximumLength !== undefined && text.length > maximumLength) {
      errors.push(`${owner}.${language}: must be at most ${maximumLength} characters`);
    }
  }
}

function validateId(value, owner, errors) {
  if (typeof value !== 'string' || !ID_PATTERN.test(value)) {
    errors.push(`${owner}: must be a canonical lowercase ASCII ID`);
  }
}

function validateControlledPath(value, pattern, owner, errors) {
  if (typeof value !== 'string' ||
      !pattern.test(value) ||
      value.includes('\\') ||
      value.includes('%') ||
      path.posix.normalize(value) !== value ||
      value.split('/').some((segment) => segment === '.' || segment === '..')) {
    errors.push(`${owner}: is not an allowed controlled relative path`);
    return false;
  }
  return true;
}

function validatePhotoMagic(buffer, mediaType) {
  if (mediaType === 'image/png') {
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    return buffer.length >= signature.length &&
      signature.every((byte, index) => buffer[index] === byte);
  }
  if (mediaType === 'image/jpeg') {
    return buffer.length >= 4 &&
      buffer[0] === 0xff &&
      buffer[1] === 0xd8 &&
      buffer[2] === 0xff &&
      buffer.at(-2) === 0xff &&
      buffer.at(-1) === 0xd9;
  }
  if (mediaType === 'image/webp') {
    return buffer.length >= 12 &&
      buffer.subarray(0, 4).toString('ascii') === 'RIFF' &&
      buffer.subarray(8, 12).toString('ascii') === 'WEBP';
  }
  return false;
}

function validatePhoto(root, photo, memberId, owner, errors, references) {
  if (photo === null) {
    return;
  }
  if (!exactKeys(
    photo,
    ['path', 'mediaType', 'sha256', 'byteLength', 'rights'],
    [],
    owner,
    errors
  )) {
    return;
  }

  const pathIsValid = validateControlledPath(
    photo.path,
    PHOTO_PATH_PATTERN,
    `${owner}.path`,
    errors
  );
  const extension = pathIsValid ? path.posix.extname(photo.path).toLowerCase() : null;
  const expectedMediaType = extension === '.png'
    ? 'image/png'
    : extension === '.jpg' || extension === '.jpeg'
      ? 'image/jpeg'
      : extension === '.webp'
        ? 'image/webp'
        : null;

  if (!['image/png', 'image/jpeg', 'image/webp'].includes(photo.mediaType)) {
    errors.push(`${owner}.mediaType: unsupported image media type`);
  } else if (expectedMediaType !== photo.mediaType) {
    errors.push(`${owner}: media type does not match the file extension`);
  }
  if (typeof photo.sha256 !== 'string' || !HASH_PATTERN.test(photo.sha256)) {
    errors.push(`${owner}.sha256: must be a lowercase SHA-256 digest`);
  }
  if (!Number.isInteger(photo.byteLength) ||
      photo.byteLength < 1 ||
      photo.byteLength > MAX_PHOTO_BYTES) {
    errors.push(`${owner}.byteLength: must be between 1 and ${MAX_PHOTO_BYTES}`);
  }

  if (pathIsValid) {
    const stem = path.posix.basename(photo.path, extension);
    if (stem !== memberId) {
      errors.push(`${owner}.path: file name must match member ID '${memberId}'`);
    }
    if (references.assets.has(photo.path)) {
      errors.push(`${owner}.path: photo path '${photo.path}' is referenced more than once`);
    }
    references.assets.add(photo.path);

    const absolutePath = path.join(root, ...photo.path.split('/'));
    if (!existsSync(absolutePath)) {
      errors.push(`${owner}.path: file '${photo.path}' does not exist`);
    } else {
      const fileInfo = lstatSync(absolutePath);
      if (fileInfo.isSymbolicLink() || !fileInfo.isFile()) {
        errors.push(`${owner}.path: '${photo.path}' must be a regular file, not a symlink`);
      } else {
        const buffer = readFileSync(absolutePath);
        if (buffer.length !== photo.byteLength) {
          errors.push(`${owner}.byteLength: does not match '${photo.path}'`);
        }
        if (sha256(buffer) !== photo.sha256) {
          errors.push(`${owner}.sha256: does not match raw bytes of '${photo.path}'`);
        }
        if (!validatePhotoMagic(buffer, photo.mediaType)) {
          errors.push(`${owner}: '${photo.path}' magic bytes do not match ${photo.mediaType}`);
        }
      }
    }
  }

  validatePhotoRights(root, photo.rights, memberId, `${owner}.rights`, errors, references);
}

function validatePhotoRights(root, rights, memberId, owner, errors, references) {
  if (!exactKeys(
    rights,
    ['basis', 'license', 'permissionPath', 'permissionSha256', 'memberConsent'],
    [],
    owner,
    errors
  )) {
    return;
  }

  if (rights.memberConsent !== true) {
    errors.push(`${owner}.memberConsent: must be true`);
  }

  if (rights.basis === 'license') {
    if (typeof rights.license !== 'string' || !SPDX_PATTERN.test(rights.license)) {
      errors.push(`${owner}.license: must be an explicit SPDX-style license identifier`);
    }
    if (rights.permissionPath !== null || rights.permissionSha256 !== null) {
      errors.push(`${owner}: licensed photos must not declare a permission record`);
    }
    return;
  }

  if (rights.basis !== 'documented-permission') {
    errors.push(`${owner}.basis: must be 'license' or 'documented-permission'`);
    return;
  }
  if (rights.license !== null) {
    errors.push(`${owner}.license: must be null for documented permission`);
  }
  const permissionPathIsValid = validateControlledPath(
    rights.permissionPath,
    PERMISSION_PATH_PATTERN,
    `${owner}.permissionPath`,
    errors
  );
  if (typeof rights.permissionSha256 !== 'string' ||
      !HASH_PATTERN.test(rights.permissionSha256)) {
    errors.push(`${owner}.permissionSha256: must be a lowercase SHA-256 digest`);
  }
  if (!permissionPathIsValid) {
    return;
  }

  const permissionStem = path.posix.basename(rights.permissionPath, '.md');
  if (permissionStem !== memberId) {
    errors.push(`${owner}.permissionPath: file name must match member ID '${memberId}'`);
  }
  if (references.permissions.has(rights.permissionPath)) {
    errors.push(
      `${owner}.permissionPath: '${rights.permissionPath}' is referenced more than once`
    );
  }
  references.permissions.add(rights.permissionPath);

  const permission = readUtf8(root, rights.permissionPath, errors);
  if (permission !== null) {
    const normalizedBytes = Buffer.from(permission.normalizedText, 'utf8');
    if (sha256(normalizedBytes) !== rights.permissionSha256) {
      errors.push(
        `${owner}.permissionSha256: does not match normalized UTF-8 LF text`
      );
    }
    const requiredStatements = [
      `Cat catalog ID: \`${memberId}\``,
      'Consent confirmed by the member\'s submitting human: yes',
      'grants Namireki Studio permission'
    ];
    for (const statement of requiredStatements) {
      if (!permission.normalizedText.includes(statement)) {
        errors.push(
          `${owner}.permissionPath: record must contain '${statement}'`
        );
      }
    }
  }
}

function validateCommonCatalog(document, expected, owner, errors) {
  if (document.$schema !== expected.schema) {
    errors.push(`${owner}.$schema: must be '${expected.schema}'`);
  }
  if (document.documentType !== 'catverter-member-catalog') {
    errors.push(`${owner}.documentType: must be 'catverter-member-catalog'`);
  }
  if (document.schemaVersion !== 1) {
    errors.push(`${owner}.schemaVersion: must be 1`);
  }
  if (document.catalogType !== expected.catalogType) {
    errors.push(`${owner}.catalogType: must be '${expected.catalogType}'`);
  }
  if (document.trust !== expected.trust) {
    errors.push(`${owner}.trust: must be '${expected.trust}'`);
  }
  validateVersion(document.version, `${owner}.version`, errors);
  validateTimestamp(document.updatedAt, `${owner}.updatedAt`, errors);
  if (document.license !== LICENSE) {
    errors.push(`${owner}.license: must be '${LICENSE}'`);
  }
  if (document.copyright !== COPYRIGHT) {
    errors.push(`${owner}.copyright: must be '${COPYRIGHT}'`);
  }
}

function validateStandardMember(root, member, index, errors, references) {
  const owner = `${STANDARD_PATH}.members[${index}]`;
  if (!exactKeys(
    member,
    ['id', 'memberType', 'catName', 'position', 'description', 'accentColor', 'photo'],
    [],
    owner,
    errors
  )) {
    return null;
  }
  validateId(member.id, `${owner}.id`, errors);
  if (member.memberType !== 'standard') {
    errors.push(`${owner}.memberType: must be 'standard'`);
  }
  if (typeof member.catName !== 'string' ||
      member.catName.trim().length === 0 ||
      member.catName.length > 100) {
    errors.push(`${owner}.catName: must be a non-empty string up to 100 characters`);
  }
  validateLocalized(member.position, `${owner}.position`, errors);
  validateLocalized(member.description, `${owner}.description`, errors);
  if (typeof member.accentColor !== 'string' ||
      !COLOR_PATTERN.test(member.accentColor)) {
    errors.push(`${owner}.accentColor: must use uppercase #RRGGBB notation`);
  }
  validatePhoto(root, member.photo, member.id, `${owner}.photo`, errors, references);
  return member.id;
}

function validatePatreonMember(
  root,
  member,
  owner,
  errors,
  references,
  validateAssets = true
) {
  if (!exactKeys(
    member,
    ['id', 'memberType', 'catName', 'position', 'photo'],
    ['description'],
    owner,
    errors
  )) {
    return null;
  }
  validateId(member.id, `${owner}.id`, errors);
  if (member.memberType !== 'patreon') {
    errors.push(`${owner}.memberType: must be 'patreon'`);
  }
  if (typeof member.catName !== 'string' ||
      member.catName.trim().length === 0 ||
      member.catName.length > 100) {
    errors.push(`${owner}.catName: must be a non-empty string up to 100 characters`);
  }
  validateLocalized(member.position, `${owner}.position`, errors, 120);
  if (Object.hasOwn(member, 'description')) {
    validateLocalized(member.description, `${owner}.description`, errors, 280);
  }
  if (validateAssets) {
    validatePhoto(root, member.photo, member.id, `${owner}.photo`, errors, references);
  } else if (member.photo !== null) {
    errors.push(`${owner}.photo: template photo must be null`);
  }
  return member.id;
}

function validateStandardCatalog(root, document, errors, references) {
  const required = [
    '$schema',
    'documentType',
    'schemaVersion',
    'catalogType',
    'trust',
    'version',
    'updatedAt',
    'license',
    'copyright',
    'committee',
    'members'
  ];
  if (!exactKeys(document, required, [], STANDARD_PATH, errors)) {
    return [];
  }
  validateCommonCatalog(document, {
    schema: '../schemas/catverter-standard-committee-v1.schema.json',
    catalogType: 'standard-committee',
    trust: 'maintainer-curated'
  }, STANDARD_PATH, errors);

  if (exactKeys(
    document.committee,
    ['title', 'description', 'statuteTitle', 'statute'],
    [],
    `${STANDARD_PATH}.committee`,
    errors
  )) {
    for (const key of ['title', 'description', 'statuteTitle', 'statute']) {
      validateLocalized(
        document.committee[key],
        `${STANDARD_PATH}.committee.${key}`,
        errors
      );
    }
  }

  if (!Array.isArray(document.members) || document.members.length === 0) {
    errors.push(`${STANDARD_PATH}.members: must contain at least one member`);
    return [];
  }
  return document.members.map((member, index) =>
    validateStandardMember(root, member, index, errors, references)
  ).filter(Boolean);
}

function validatePatreonCatalog(root, document, errors, references) {
  const required = [
    '$schema',
    'documentType',
    'schemaVersion',
    'catalogType',
    'trust',
    'version',
    'updatedAt',
    'license',
    'copyright',
    'title',
    'description',
    'members'
  ];
  if (!exactKeys(document, required, [], PATREON_PATH, errors)) {
    return [];
  }
  validateCommonCatalog(document, {
    schema: '../schemas/catverter-patreon-members-v1.schema.json',
    catalogType: 'patreon',
    trust: 'member-submitted'
  }, PATREON_PATH, errors);
  validateLocalized(document.title, `${PATREON_PATH}.title`, errors);
  validateLocalized(document.description, `${PATREON_PATH}.description`, errors);

  if (!Array.isArray(document.members)) {
    errors.push(`${PATREON_PATH}.members: must be an array`);
    return [];
  }
  return document.members.map((member, index) =>
    validatePatreonMember(
      root,
      member,
      `${PATREON_PATH}.members[${index}]`,
      errors,
      references
    )
  ).filter(Boolean);
}

function validateManifest(root, manifestFile, errors) {
  const manifest = manifestFile.value;
  const required = [
    '$schema',
    'documentType',
    'schemaVersion',
    'version',
    'updatedAt',
    'repository',
    'ref',
    'contentBaseUrlTemplate',
    'hashAlgorithm',
    'textHashEncoding',
    'catalogs',
    'legacy'
  ];
  if (!exactKeys(manifest, required, [], MANIFEST_PATH, errors)) {
    return;
  }

  const expectedScalars = {
    '$schema': 'schemas/catverter-member-catalog-manifest-v1.schema.json',
    documentType: 'catverter-member-catalog-manifest',
    schemaVersion: 1,
    repository: 'https://github.com/namireki/catverter-members',
    ref: 'main',
    contentBaseUrlTemplate:
      'https://raw.githubusercontent.com/namireki/catverter-members/{revision}/',
    hashAlgorithm: 'sha256',
    textHashEncoding: 'utf-8-lf'
  };
  for (const [key, expected] of Object.entries(expectedScalars)) {
    if (manifest[key] !== expected) {
      errors.push(`${MANIFEST_PATH}.${key}: must be '${expected}'`);
    }
  }
  validateVersion(manifest.version, `${MANIFEST_PATH}.version`, errors);
  validateTimestamp(manifest.updatedAt, `${MANIFEST_PATH}.updatedAt`, errors);

  if (!Array.isArray(manifest.catalogs) ||
      manifest.catalogs.length !== EXPECTED_CATALOGS.length) {
    errors.push(`${MANIFEST_PATH}.catalogs: must list exactly two catalogs`);
  } else {
    manifest.catalogs.forEach((entry, index) => {
      const owner = `${MANIFEST_PATH}.catalogs[${index}]`;
      if (!exactKeys(
        entry,
        ['catalogType', 'path', 'schemaPath', 'sha256', 'byteLength'],
        [],
        owner,
        errors
      )) {
        return;
      }
      const expected = EXPECTED_CATALOGS[index];
      for (const key of ['catalogType', 'path', 'schemaPath']) {
        if (entry[key] !== expected[key]) {
          errors.push(`${owner}.${key}: must be '${expected[key]}'`);
        }
      }
      if (typeof entry.sha256 !== 'string' || !HASH_PATTERN.test(entry.sha256)) {
        errors.push(`${owner}.sha256: must be a lowercase SHA-256 digest`);
      }
      if (!Number.isInteger(entry.byteLength) || entry.byteLength < 1) {
        errors.push(`${owner}.byteLength: must be a positive integer`);
      }

      const catalogFile = readUtf8(root, expected.path, errors);
      if (catalogFile !== null) {
        const normalizedBytes = Buffer.from(catalogFile.normalizedText, 'utf8');
        if (entry.sha256 !== sha256(normalizedBytes)) {
          errors.push(`${owner}.sha256: does not match normalized UTF-8 LF catalog`);
        }
        if (entry.byteLength !== normalizedBytes.length) {
          errors.push(`${owner}.byteLength: does not match normalized catalog bytes`);
        }
      }
      if (!existsSync(path.join(root, ...expected.schemaPath.split('/')))) {
        errors.push(`${owner}.schemaPath: file '${expected.schemaPath}' does not exist`);
      }
    });
  }

  if (exactKeys(
    manifest.legacy,
    ['path', 'status', 'replacement'],
    [],
    `${MANIFEST_PATH}.legacy`,
    errors
  )) {
    const expectedLegacy = {
      path: LEGACY_PATH,
      status: 'deprecated',
      replacement: STANDARD_PATH
    };
    for (const [key, expected] of Object.entries(expectedLegacy)) {
      if (manifest.legacy[key] !== expected) {
        errors.push(`${MANIFEST_PATH}.legacy.${key}: must be '${expected}'`);
      }
    }
  }
}

function validateSchemas(root, errors) {
  for (const schemaPath of REQUIRED_SCHEMAS) {
    const schemaFile = readJson(root, schemaPath, errors);
    if (schemaFile === null) {
      continue;
    }
    const schema = schemaFile.value;
    if (schema.$schema !== 'https://json-schema.org/draft/2020-12/schema') {
      errors.push(`${schemaPath}.$schema: must declare JSON Schema 2020-12`);
    }
    if (typeof schema.$id !== 'string' || schema.$id.length === 0) {
      errors.push(`${schemaPath}.$id: must be a non-empty stable identifier`);
    }
    if (schema.$comment === undefined ||
        !schema.$comment.includes(COPYRIGHT) ||
        !schema.$comment.includes(LICENSE)) {
      errors.push(`${schemaPath}.$comment: must declare copyright and Apache-2.0`);
    }
    if (schema.type !== 'object' || schema.additionalProperties !== false) {
      errors.push(`${schemaPath}: root must be a closed object schema`);
    }
  }
}

function validateLegacyMirror(legacy, standard, errors) {
  const required = [
    '$schema',
    'documentType',
    'schemaVersion',
    'version',
    'updatedAt',
    'committee',
    'members'
  ];
  if (!exactKeys(legacy, required, [], LEGACY_PATH, errors)) {
    return;
  }
  if (legacy.$schema !== 'schemas/catverter-committee-v1.schema.json') {
    errors.push(`${LEGACY_PATH}.$schema: unexpected compatibility schema`);
  }
  if (legacy.documentType !== 'catverter-committee' || legacy.schemaVersion !== 1) {
    errors.push(`${LEGACY_PATH}: invalid compatibility document identity`);
  }
  if (legacy.version !== standard.version ||
      legacy.updatedAt !== standard.updatedAt ||
      JSON.stringify(legacy.committee) !== JSON.stringify(standard.committee)) {
    errors.push(`${LEGACY_PATH}: metadata must mirror the standard catalog exactly`);
  }
  if (!Array.isArray(legacy.members) ||
      legacy.members.length !== standard.members.length) {
    errors.push(`${LEGACY_PATH}.members: must mirror every standard member`);
    return;
  }

  legacy.members.forEach((member, index) => {
    const standardMember = standard.members[index];
    const owner = `${LEGACY_PATH}.members[${index}]`;
    if (!exactKeys(
      member,
      ['id', 'name', 'role', 'biography', 'accentColor', 'imageUrl'],
      [],
      owner,
      errors
    )) {
      return;
    }
    const expected = {
      id: standardMember.id,
      name: standardMember.catName,
      role: standardMember.position,
      biography: standardMember.description,
      accentColor: standardMember.accentColor,
      imageUrl: null
    };
    if (JSON.stringify(member) !== JSON.stringify(expected)) {
      errors.push(`${owner}: must be the ordered compatibility projection`);
    }
  });
}

function walkRegularFiles(root, relativeDirectory) {
  const directory = path.join(root, ...relativeDirectory.split('/'));
  if (!existsSync(directory)) {
    return [];
  }
  const files = [];
  const visit = (absoluteDirectory) => {
    for (const entry of readdirSync(absoluteDirectory, { withFileTypes: true })) {
      const absolutePath = path.join(absoluteDirectory, entry.name);
      if (entry.isDirectory()) {
        visit(absolutePath);
      } else if (entry.isFile()) {
        files.push(displayPath(root, absolutePath));
      } else if (entry.isSymbolicLink()) {
        files.push(displayPath(root, absolutePath));
      }
    }
  };
  visit(directory);
  return files.sort();
}

function validateNoStaleFiles(root, references, errors) {
  const assetFiles = walkRegularFiles(root, 'assets/photos');
  const permissionFiles = walkRegularFiles(root, 'permissions');
  for (const file of assetFiles) {
    if (!references.assets.has(file)) {
      errors.push(`${file}: unreferenced photo file is not allowed`);
    }
  }
  for (const file of permissionFiles) {
    if (!references.permissions.has(file)) {
      errors.push(`${file}: unreferenced permission record is not allowed`);
    }
  }
}

function validateTemplates(root, errors) {
  const templatePath = 'templates/patreon-member.template.json';
  const template = readJson(root, templatePath, errors);
  if (template !== null) {
    validatePatreonMember(
      root,
      template.value,
      templatePath,
      errors,
      { assets: new Set(), permissions: new Set() },
      false
    );
  }
  const permissionTemplate = readUtf8(
    root,
    'templates/photo-permission.template.md',
    errors
  );
  if (permissionTemplate !== null &&
      (!permissionTemplate.text.includes(COPYRIGHT) ||
       !permissionTemplate.text.includes(LICENSE))) {
    errors.push(
      'templates/photo-permission.template.md: must declare copyright and Apache-2.0'
    );
  }
}

function validateLicenseFiles(root, errors) {
  const license = readUtf8(root, 'LICENSE', errors);
  if (license !== null &&
      (!license.text.includes('Apache License') ||
       !license.text.includes('Version 2.0'))) {
    errors.push('LICENSE: must contain the Apache License 2.0 text');
  }
  const notice = readUtf8(root, 'NOTICE', errors);
  if (notice !== null && !notice.text.includes(COPYRIGHT)) {
    errors.push(`NOTICE: must contain '${COPYRIGHT}'`);
  }
}

export function validateRepository(root) {
  const absoluteRoot = path.resolve(root);
  const errors = [];
  const references = {
    assets: new Set(),
    permissions: new Set()
  };

  validateLicenseFiles(absoluteRoot, errors);
  validateSchemas(absoluteRoot, errors);
  validateTemplates(absoluteRoot, errors);

  const manifest = readJson(absoluteRoot, MANIFEST_PATH, errors);
  if (manifest !== null) {
    validateManifest(absoluteRoot, manifest, errors);
  }

  const standardFile = readJson(absoluteRoot, STANDARD_PATH, errors);
  const patreonFile = readJson(absoluteRoot, PATREON_PATH, errors);
  const standardIds = standardFile === null
    ? []
    : validateStandardCatalog(
      absoluteRoot,
      standardFile.value,
      errors,
      references
    );
  const patreonIds = patreonFile === null
    ? []
    : validatePatreonCatalog(
      absoluteRoot,
      patreonFile.value,
      errors,
      references
    );

  const seenIds = new Map();
  for (const [catalogType, ids] of [
    ['standard', standardIds],
    ['patreon', patreonIds]
  ]) {
    for (const id of ids) {
      if (seenIds.has(id)) {
        errors.push(
          `member ID '${id}' in ${catalogType} catalog conflicts with ` +
          `${seenIds.get(id)} catalog`
        );
      } else {
        seenIds.set(id, catalogType);
      }
    }
  }

  const legacyFile = readJson(absoluteRoot, LEGACY_PATH, errors);
  if (legacyFile !== null && standardFile !== null) {
    validateLegacyMirror(legacyFile.value, standardFile.value, errors);
  }
  validateNoStaleFiles(absoluteRoot, references, errors);

  return {
    errors,
    counts: {
      standard: standardIds.length,
      patreon: patreonIds.length,
      photos: references.assets.size
    }
  };
}

function runCli() {
  const scriptPath = fileURLToPath(import.meta.url);
  const defaultRoot = path.resolve(path.dirname(scriptPath), '..');
  const root = process.argv[2] ?? defaultRoot;
  const result = validateRepository(root);
  if (result.errors.length > 0) {
    console.error(`Member catalog repository has ${result.errors.length} problem(s):`);
    result.errors.forEach((error) => console.error(`- ${error}`));
    process.exitCode = 1;
    return;
  }
  console.log(
    'Member catalogs are valid: ' +
    `${result.counts.standard} standard, ` +
    `${result.counts.patreon} Patreon, ` +
    `${result.counts.photos} photos.`
  );
}

const invokedPath = process.argv[1] === undefined
  ? null
  : pathToFileURL(path.resolve(process.argv[1])).href;
if (invokedPath === import.meta.url) {
  runCli();
}
