import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  cpSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { validateRepository } from '../tools/validate.mjs';

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..'
);
const patreonFixturePath = 'test/fixtures/patreon-members-20.json';
const pngBytes = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z6h8AAAAASUVORK5CYII=',
  'base64'
);

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function normalizeLf(value) {
  return value.replace(/\r\n?/g, '\n');
}

function readJson(root, relativePath) {
  return JSON.parse(readFileSync(path.join(root, relativePath), 'utf8'));
}

function writeJson(root, relativePath, value, eol = '\n') {
  const text = `${JSON.stringify(value, null, 2)}\n`.replace(/\n/g, eol);
  writeFileSync(path.join(root, relativePath), text, 'utf8');
}

function refreshManifest(root) {
  const manifest = readJson(root, 'catalog.json');
  for (const entry of manifest.catalogs) {
    const text = readFileSync(path.join(root, entry.path), 'utf8');
    const normalizedBytes = Buffer.from(normalizeLf(text), 'utf8');
    entry.sha256 = sha256(normalizedBytes);
    entry.byteLength = normalizedBytes.length;
  }
  writeJson(root, 'catalog.json', manifest);
}

function withFixture(callback) {
  const root = mkdtempSync(path.join(tmpdir(), 'catverter-members-'));
  try {
    cpSync(repositoryRoot, root, {
      recursive: true,
      filter: (source) => {
        const name = path.basename(source);
        return name !== '.git' && name !== 'node_modules';
      }
    });
    callback(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function licensedPhoto(id) {
  return {
    path: `assets/photos/${id}.png`,
    mediaType: 'image/png',
    sha256: sha256(pngBytes),
    byteLength: pngBytes.length,
    rights: {
      basis: 'license',
      license: 'CC-BY-4.0',
      permissionPath: null,
      permissionSha256: null,
      memberConsent: true
    }
  };
}

function patreonMember(id, photo = null, premiumSortOrder) {
  const member = {
    id,
    memberType: 'patreon',
    catName: 'Miso',
    position: {
      en: 'Assistant Box Inspector'
    },
    description: {
      en: 'Checks whether every box is sufficiently occupied.'
    },
    photo
  };
  if (premiumSortOrder !== undefined) {
    member.premiumSortOrder = premiumSortOrder;
  }
  return member;
}

function writePatreonWithRawPremiumSortOrder(
  root,
  rawValue,
  { duplicate = false } = {}
) {
  const patreon = readJson(root, 'catalogs/patreon-members.json');
  patreon.members.push(patreonMember('miso', null, 1));
  const marker = '"premiumSortOrder": 1';
  const replacement = duplicate
    ? `${marker},\n      "premiumSortOrder": ${rawValue}`
    : `"premiumSortOrder": ${rawValue}`;
  const text = `${JSON.stringify(patreon, null, 2)}\n`;
  assert(text.includes(marker));
  writeFileSync(
    path.join(root, 'catalogs/patreon-members.json'),
    text.replace(marker, replacement),
    'utf8'
  );
  refreshManifest(root);
}

function groupPatreonMembersForConsumer(members) {
  const premiumGroups = new Map();
  const defaultMembers = [];
  for (const member of members) {
    if (!Object.hasOwn(member, 'premiumSortOrder')) {
      defaultMembers.push(member);
      continue;
    }
    const group = premiumGroups.get(member.premiumSortOrder) ?? [];
    group.push(member);
    premiumGroups.set(member.premiumSortOrder, group);
  }
  return [
    ...[...premiumGroups.entries()]
      .sort(([left], [right]) => left - right)
      .map(([premiumSortOrder, groupMembers]) => ({
        premiumSortOrder,
        members: groupMembers
      })),
    {
      premiumSortOrder: null,
      members: defaultMembers
    }
  ];
}

test('canonical repository validates with expected counts', () => {
  const result = validateRepository(repositoryRoot);
  assert.deepEqual(result.errors, []);
  assert.deepEqual(result.counts, {
    standard: 5,
    patreon: 0,
    photos: 0
  });
});

test('test-only Patreon UI fixture injects exactly 20 valid members', () => {
  withFixture((root) => {
    const fixture = readJson(root, patreonFixturePath);
    assert.equal(fixture.fixtureType, 'catverter-patreon-members-test-only');
    assert.equal(fixture.testingOnly, true);
    assert.equal(fixture.publicManifestIncluded, false);
    assert.equal(fixture.members.length, 20);
    assert(fixture.members.every((member) =>
      member.id.startsWith('test-patreon-')
    ));
    const consumerGroups = groupPatreonMembersForConsumer(fixture.members);
    assert.deepEqual(
      consumerGroups.map((group) => group.premiumSortOrder),
      [0, 10, null]
    );
    assert.deepEqual(
      consumerGroups[0].members.map((member) => member.id).sort(),
      ['test-patreon-pip', 'test-patreon-pixel']
    );
    assert.deepEqual(
      consumerGroups[1].members.map((member) => member.id),
      ['test-patreon-maximum-whiskers']
    );
    assert.equal(consumerGroups[2].members.length, 17);
    assert(consumerGroups.slice(0, -1).every((group) =>
      group.members.every((member) =>
        Object.hasOwn(member, 'premiumSortOrder')
      )
    ));
    assert(consumerGroups.at(-1).members.every((member) =>
      !Object.hasOwn(member, 'premiumSortOrder')
    ));

    const manifest = readJson(root, 'catalog.json');
    assert.equal(
      manifest.catalogs.some((catalog) => catalog.path === patreonFixturePath),
      false
    );

    const patreon = readJson(root, 'catalogs/patreon-members.json');
    assert.deepEqual(patreon.members, []);
    patreon.members.push(...fixture.members);
    writeJson(root, 'catalogs/patreon-members.json', patreon);
    refreshManifest(root);

    const result = validateRepository(root);
    assert.deepEqual(result.errors, []);
    assert.deepEqual(result.counts, {
      standard: 5,
      patreon: 20,
      photos: 0
    });
  });
});

test('schemas expose premium ordering only for Patreon members', () => {
  const patreonSchema = readJson(
    repositoryRoot,
    'schemas/catverter-patreon-members-v1.schema.json'
  );
  assert.deepEqual(
    patreonSchema.$defs.member.properties.premiumSortOrder,
    {
      type: 'integer',
      minimum: 0,
      maximum: 2147483647
    }
  );
  assert.equal(
    patreonSchema.$defs.member.required.includes('premiumSortOrder'),
    false
  );

  const standardSchema = readJson(
    repositoryRoot,
    'schemas/catverter-standard-committee-v1.schema.json'
  );
  assert.equal(standardSchema.$defs.member.additionalProperties, false);
  assert.equal(
    Object.hasOwn(
      standardSchema.$defs.member.properties,
      'premiumSortOrder'
    ),
    false
  );
});

test('premiumSortOrder accepts missing, zero, and signed 32-bit maximum', () => {
  withFixture((root) => {
    const patreon = readJson(root, 'catalogs/patreon-members.json');
    patreon.members.push(
      patreonMember('default-miso'),
      patreonMember('premium-zero', null, 0),
      patreonMember('premium-max', null, 2147483647)
    );
    writeJson(root, 'catalogs/patreon-members.json', patreon);
    refreshManifest(root);

    assert.deepEqual(validateRepository(root).errors, []);
  });
});

for (const [label, rawValue] of [
  ['negative values', '-1'],
  ['fractions', '1.5'],
  ['decimal integer spellings', '1.0'],
  ['exponent spellings', '1e0'],
  ['strings', '"1"'],
  ['null', 'null'],
  ['booleans', 'true'],
  ['signed 32-bit overflow', '2147483648']
]) {
  test(`premiumSortOrder rejects ${label}`, () => {
    withFixture((root) => {
      writePatreonWithRawPremiumSortOrder(root, rawValue);

      const result = validateRepository(root);
      assert(result.errors.some((error) =>
        error.includes('.premiumSortOrder:')
      ));
    });
  });
}

test('duplicate premiumSortOrder keys are rejected before JSON parsing can hide them', () => {
  withFixture((root) => {
    writePatreonWithRawPremiumSortOrder(root, '2', { duplicate: true });

    const result = validateRepository(root);
    assert(result.errors.some((error) =>
      error.includes("duplicate property 'premiumSortOrder'")
    ));
  });
});

test('standard committee members reject premiumSortOrder', () => {
  withFixture((root) => {
    const standard = readJson(root, 'catalogs/standard-committee.json');
    standard.members[0].premiumSortOrder = 0;
    writeJson(root, 'catalogs/standard-committee.json', standard);
    refreshManifest(root);

    const result = validateRepository(root);
    assert(result.errors.some((error) =>
      error.includes("unknown property 'premiumSortOrder'")
    ));
  });
});

test('standard catalog preserves the exact five-member migration', () => {
  const standard = readJson(repositoryRoot, 'catalogs/standard-committee.json');
  assert.equal(standard.version, '1.0.0');
  assert.equal(standard.updatedAt, '2026-10-24T00:00:00Z');
  assert.deepEqual(standard.committee, {
    title: {
      en: 'The Committee',
      it: 'Il Comitato'
    },
    description: {
      en: 'The authority that translates incomprehensible human units into units that make immediate sense from a feline point of view.',
      it: "L'autorità che traduce le incomprensibili unità di misura umane in unità che abbiano senso immediato dal punto di vista felino."
    },
    statuteTitle: {
      en: 'Official statute',
      it: 'Statuto ufficiale'
    },
    statute: {
      en: 'Under M.E.O.W. Directive 9/9 (Ministry for the Evaluation of Observational Weirdness), the Committee shall ensure that every quantity can be expressed through cat-perceivable equivalents.',
      it: "Ai sensi della Direttiva M.I.A.O. 9/9 (Ministero per l'Interpretazione delle Astrazioni Osservative), il Comitato è incaricato di garantire che ogni quantità possa essere espressa mediante equivalenze gattosamente percepibili."
    }
  });
  assert.deepEqual(
    standard.members.map((member) => ({
      id: member.id,
      catName: member.catName,
      position: member.position,
      description: member.description,
      accentColor: member.accentColor,
      photo: member.photo
    })),
    [
      {
        id: 'pigro',
        catName: 'Pigro',
        position: {
          en: 'President of Applied Measurements',
          it: 'Presidente delle Misure Applicate'
        },
        description: {
          en: 'Calls meetings by sitting on the agenda and decides whether a unit deserves official recognition in the catverse.',
          it: "Convoca le riunioni sedendosi sull'ordine del giorno e decide se un'unità merita il riconoscimento ufficiale del catverso."
        },
        accentColor: '#F3B13F',
        photo: null
      },
      {
        id: 'gino',
        catName: 'Gino',
        position: {
          en: 'Inspector of Suspicious Heat',
          it: 'Ispettore del calore sospetto'
        },
        description: {
          en: 'Certifies that every object declared “hot” has first been tested with an official paw touch and, when required, a spectacular retreat.',
          it: 'Certifica che ogni oggetto dichiarato “caldo” sia stato preventivamente testato mediante apposito tocco con zampa ed eventuale fuga spettacolare.'
        },
        accentColor: '#EBC45C',
        photo: null
      },
      {
        id: 'ludovico',
        catName: 'Ludovico',
        position: {
          en: 'Supreme Reviewer of Naps',
          it: 'Revisore Supremo dei Sonnellini'
        },
        description: {
          en: 'Checks units of time against the only reliable clock: whether a nap was short, correct, or interrupted with appropriate cursing.',
          it: "Controlla le unità di tempo con l'unico orologio affidabile: se il sonnellino è stato breve, corretto o interrotto con maleducazione."
        },
        accentColor: '#BACD8A',
        photo: null
      },
      {
        id: 'agata',
        catName: 'Agata',
        position: {
          en: 'Director of Vertical Ambition',
          it: "Direttore dell'Ambizione Verticale"
        },
        description: {
          en: 'Evaluates height, distance, and jumping measurements. Human declarations are corrected according to feline climbing standards.',
          it: 'Valuta tutte le misure di altezza, distanza e salto. Le dichiarazioni umane vengono corrette secondo gli standard felini di arrampicabilità.'
        },
        accentColor: '#C9ADEE',
        photo: null
      },
      {
        id: 'seat-five',
        catName: 'Seggio Cinque',
        position: {
          en: 'Officer for Air Currents',
          it: "Responsabile delle correnti d'aria"
        },
        description: {
          en: 'Asks to leave when the door is closed, then declines to leave. Once the door closes again, the cycle resumes.',
          it: 'Chiede di uscire quando la porta è chiusa, per poi non uscire affatto. Se la porta viene chiusa, il ciclo ricomincia.'
        },
        accentColor: '#8CCFE5',
        photo: null
      }
    ]
  );
});

test('Patreon IDs cannot replace standard committee IDs', () => {
  withFixture((root) => {
    const patreon = readJson(root, 'catalogs/patreon-members.json');
    patreon.members.push(patreonMember('pigro'));
    writeJson(root, 'catalogs/patreon-members.json', patreon);
    refreshManifest(root);

    const result = validateRepository(root);
    assert(result.errors.some((error) =>
      error.includes("member ID 'pigro' in patreon catalog conflicts with standard")
    ));
  });
});

test('unknown properties and noncanonical language tags are rejected', () => {
  withFixture((root) => {
    const patreon = readJson(root, 'catalogs/patreon-members.json');
    const member = patreonMember('Miso');
    member.position['en-us'] = 'Regional Box Inspector';
    member.position.en = ' ';
    member.untrusted = true;
    patreon.members.push(member);
    writeJson(root, 'catalogs/patreon-members.json', patreon);
    refreshManifest(root);

    const result = validateRepository(root);
    assert(result.errors.some((error) => error.includes("unknown property 'untrusted'")));
    assert(result.errors.some((error) =>
      error.includes('must be a canonical lowercase ASCII ID')
    ));
    assert(result.errors.some((error) =>
      error.includes('position.en: must be a non-empty string')
    ));
    assert(result.errors.some((error) =>
      error.includes("language tag 'en-us' must be canonical 'en-US'")
    ));
  });
});

test('a repository-hosted licensed photo validates by raw hash, length, and magic', () => {
  withFixture((root) => {
    mkdirSync(path.join(root, 'assets', 'photos'), { recursive: true });
    writeFileSync(path.join(root, 'assets', 'photos', 'miso.png'), pngBytes);
    const patreon = readJson(root, 'catalogs/patreon-members.json');
    patreon.members.push(patreonMember('miso', licensedPhoto('miso')));
    writeJson(root, 'catalogs/patreon-members.json', patreon);
    refreshManifest(root);

    assert.deepEqual(validateRepository(root).errors, []);
  });
});

test('documented photo permission is checked and hash-bound', () => {
  withFixture((root) => {
    mkdirSync(path.join(root, 'assets', 'photos'), { recursive: true });
    mkdirSync(path.join(root, 'permissions'), { recursive: true });
    writeFileSync(path.join(root, 'assets', 'photos', 'miso.png'), pngBytes);
    const permission = [
      '# Photo permission for `miso`',
      '',
      '- Cat catalog ID: `miso`',
      '- Consent confirmed by the member\'s submitting human: yes',
      '',
      'The rights holder grants Namireki Studio permission to display this photo.',
      ''
    ].join('\n');
    writeFileSync(path.join(root, 'permissions', 'miso.md'), permission, 'utf8');

    const photo = licensedPhoto('miso');
    photo.rights = {
      basis: 'documented-permission',
      license: null,
      permissionPath: 'permissions/miso.md',
      permissionSha256: sha256(Buffer.from(permission, 'utf8')),
      memberConsent: true
    };
    const patreon = readJson(root, 'catalogs/patreon-members.json');
    patreon.members.push(patreonMember('miso', photo));
    writeJson(root, 'catalogs/patreon-members.json', patreon);
    refreshManifest(root);

    assert.deepEqual(validateRepository(root).errors, []);
  });
});

test('photo tampering and stale files are rejected', () => {
  withFixture((root) => {
    mkdirSync(path.join(root, 'assets', 'photos'), { recursive: true });
    writeFileSync(path.join(root, 'assets', 'photos', 'miso.png'), pngBytes);
    writeFileSync(path.join(root, 'assets', 'photos', 'orphan.png'), pngBytes);
    const patreon = readJson(root, 'catalogs/patreon-members.json');
    const photo = licensedPhoto('miso');
    photo.sha256 = '0'.repeat(64);
    photo.byteLength += 1;
    photo.mediaType = 'image/jpeg';
    patreon.members.push(patreonMember('miso', photo));
    writeJson(root, 'catalogs/patreon-members.json', patreon);
    refreshManifest(root);

    const result = validateRepository(root);
    assert(result.errors.some((error) => error.includes('does not match raw bytes')));
    assert(result.errors.some((error) =>
      error.includes('byteLength: does not match')
    ));
    assert(result.errors.some((error) => error.includes('magic bytes do not match')));
    assert(result.errors.some((error) =>
      error.includes('media type does not match the file extension')
    ));
    assert(result.errors.some((error) =>
      error.includes('unreferenced photo file is not allowed')
    ));
  });
});

test('versions, timestamps, and colors use canonical formats', () => {
  withFixture((root) => {
    const patreon = readJson(root, 'catalogs/patreon-members.json');
    patreon.version = '01.2';
    patreon.updatedAt = '2026-02-30T00:00:00Z';
    writeJson(root, 'catalogs/patreon-members.json', patreon);

    const standard = readJson(root, 'catalogs/standard-committee.json');
    standard.members[0].accentColor = '#f3b13f';
    writeJson(root, 'catalogs/standard-committee.json', standard);
    refreshManifest(root);

    const result = validateRepository(root);
    assert(result.errors.some((error) =>
      error.includes('must be a three-component dotted version')
    ));
    assert(result.errors.some((error) =>
      error.includes('must be a real canonical ISO-8601 UTC timestamp')
    ));
    assert(result.errors.some((error) =>
      error.includes('must use uppercase #RRGGBB notation')
    ));
  });
});

test('photo path traversal and external locations are rejected', () => {
  withFixture((root) => {
    const patreon = readJson(root, 'catalogs/patreon-members.json');
    const photo = licensedPhoto('miso');
    photo.path = '../miso.png';
    patreon.members.push(patreonMember('miso', photo));
    writeJson(root, 'catalogs/patreon-members.json', patreon);
    refreshManifest(root);

    const result = validateRepository(root);
    assert(result.errors.some((error) =>
      error.includes('is not an allowed controlled relative path')
    ));
  });
});

test('manifest text hashes normalize CRLF to LF', () => {
  withFixture((root) => {
    const patreon = readJson(root, 'catalogs/patreon-members.json');
    writeJson(root, 'catalogs/patreon-members.json', patreon, '\r\n');
    refreshManifest(root);

    assert.deepEqual(validateRepository(root).errors, []);
  });
});

test('legacy compatibility roster cannot drift from the standard catalog', () => {
  withFixture((root) => {
    const legacy = readJson(root, 'committee.json');
    legacy.members[0].name = 'Not Pigro';
    writeJson(root, 'committee.json', legacy);

    const result = validateRepository(root);
    assert(result.errors.some((error) =>
      error.includes('must be the ordered compatibility projection')
    ));
  });
});
