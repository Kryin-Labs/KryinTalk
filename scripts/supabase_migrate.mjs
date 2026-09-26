// Apply named, reviewed migrations atomically, including CLI migration history.
// Usage: SUPABASE_ACCESS_TOKEN=... node scripts/supabase_migrate.mjs <filename.sql> ...
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const token = process.env.SUPABASE_ACCESS_TOKEN;
if (!token) throw new Error('SUPABASE_ACCESS_TOKEN is required');
const files = process.argv.slice(2);
if (!files.length) throw new Error('Specify migration filenames');
async function query(sql) {
  const response = await fetch('https://api.supabase.com/v1/projects/mujhkmuhlmuqbansrdwp/database/query', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
    signal: AbortSignal.timeout(60000),
  });
  if (!response.ok) throw new Error(`Migration HTTP ${response.status}: ${(await response.text()).replaceAll(token, '[REDACTED]')}`);
  return response.json();
}
for (const file of files) {
  const match = file.match(/^(\d{14})_([a-z0-9_]+)\.sql$/);
  if (!match) throw new Error('Expected a migration filename, without directories');
  const [, version, name] = match;
  const existing = await query(`SELECT version FROM supabase_migrations.schema_migrations WHERE version = '${version}'`);
  if (existing.length) { console.log(`${file}: already applied`); continue; }
  const sql = readFileSync(resolve(root, 'supabase/migrations', file), 'utf8')
    .replace(/^\s*(BEGIN|COMMIT);\s*$/gm, '');
  await query(`BEGIN;\n${sql}\nINSERT INTO supabase_migrations.schema_migrations(version, name, statements) VALUES ('${version}', '${name}', ARRAY['${sql.replaceAll("'", "''")}']);\nCOMMIT;`);
  console.log(`${file}: applied`);
}
