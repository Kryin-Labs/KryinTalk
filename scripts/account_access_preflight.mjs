// Read-only catalog snapshot. No identity rows, tokens, or message content.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
const token = process.env.SUPABASE_ACCESS_TOKEN;
if (!token) throw new Error('SUPABASE_ACCESS_TOKEN is unavailable');
const response = await fetch('https://api.supabase.com/v1/projects/mujhkmuhlmuqbansrdwp/database/query', {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({query: readFileSync('supabase/verification/account_access_preflight.sql', 'utf8')}),
});
if (!response.ok) throw new Error(`Read-only preflight HTTP ${response.status}`);
mkdirSync('tools/account-access-test', {recursive:true});
writeFileSync('tools/account-access-test/preflight.json', JSON.stringify(await response.json(), null, 2));
console.log('Read-only catalog saved locally.');
