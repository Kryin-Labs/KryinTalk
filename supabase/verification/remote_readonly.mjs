// Read-only catalog/aggregate verification. Never prints environment values.
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const config = { ...process.env };
try {
  for (const line of readFileSync(resolve(root, '.env'), 'utf8').split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (match && !config[match[1]]) config[match[1]] = match[2].replace(/^(['"])(.*)\1$/, '$2');
  }
} catch { /* Environment-only configuration is supported. */ }
const token = config.SUPABASE_ACCESS_TOKEN;
if (!token) throw new Error('SUPABASE_ACCESS_TOKEN is required in the environment or .env');
const sqlPath = resolve(root, process.argv[2] ?? 'supabase/verification/catalog.sql');
if (!sqlPath.startsWith(resolve(root, 'supabase/verification') + '/'.replace('/', process.platform === 'win32' ? '\\' : '/'))) {
  throw new Error('Only verification SQL files may be used');
}
const query = readFileSync(sqlPath, 'utf8');
try {
  const response = await fetch('https://api.supabase.com/v1/projects/mujhkmuhlmuqbansrdwp/database/query', {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: `BEGIN TRANSACTION READ ONLY;\n${query}\nROLLBACK;`, read_only: true }),
    signal: AbortSignal.timeout(45000),
  });
  if (!response.ok) {
    console.error(`Verification HTTP ${response.status}`);
    // Catalog SQL contains no credentials or user rows; suppress other payloads.
    const error = await response.json().catch(() => ({}));
    console.error(String(error.message ?? error.error ?? 'Query rejected').replaceAll(token, '[REDACTED]'));
    process.exitCode = 1;
  } else console.log(JSON.stringify(await response.json(), null, 2));
} catch (error) {
  console.error(`Verification connection failed: ${error.cause?.code ?? error.name}`);
  process.exitCode = 1;
}
