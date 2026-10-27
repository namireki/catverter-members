import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const repositoryRoot = path.resolve(path.dirname(scriptPath), '..');
const manifestPath = path.join(repositoryRoot, 'catalog.json');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));

for (const entry of manifest.catalogs) {
  const catalogPath = path.join(repositoryRoot, ...entry.path.split('/'));
  const normalizedText = readFileSync(catalogPath, 'utf8').replace(/\r\n?/g, '\n');
  const normalizedBytes = Buffer.from(normalizedText, 'utf8');
  entry.sha256 = createHash('sha256').update(normalizedBytes).digest('hex');
  entry.byteLength = normalizedBytes.length;
}

writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
console.log('Updated catalog.json hashes and normalized byte lengths.');
