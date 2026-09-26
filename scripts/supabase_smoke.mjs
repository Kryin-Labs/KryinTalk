// Authenticated, read-only app smoke checks; never prints credentials or rows.
// Set KRYINTALK_TEST_EMAIL and KRYINTALK_TEST_PASSWORD in the environment.
const base = 'https://mujhkmuhlmuqbansrdwp.supabase.co';
const headers = { apikey: 'sb_publishable_DynSSVBOhrg7pIwspvUT8w_ebavdq28', 'Content-Type': 'application/json' };
if (!process.env.KRYINTALK_TEST_EMAIL || !process.env.KRYINTALK_TEST_PASSWORD) {
  throw new Error('KRYINTALK_TEST_EMAIL and KRYINTALK_TEST_PASSWORD are required');
}
async function request(path, body) {
  const response = await fetch(base + path, {
    method: body === undefined ? 'GET' : 'POST', headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(30000),
  });
  const data = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${path}: HTTP ${response.status} ${data?.code ?? ''} ${data?.message ?? ''}`);
  return data;
}
const auth = await request('/auth/v1/token?grant_type=password', {
  email: process.env.KRYINTALK_TEST_EMAIL, password: process.env.KRYINTALK_TEST_PASSWORD,
});
if (!auth.access_token || !auth.user?.id) throw new Error('Missing Auth session');
console.log('Password login: PASS');
headers.Authorization = `Bearer ${auth.access_token}`;
try {
  const profile = await request('/rest/v1/rpc/get_current_user_profile', {});
  if (profile?.id !== auth.user.id) throw new Error('Profile does not match signed-in account');
  if ('password_hash' in profile) throw new Error('Profile exposed a password hash');
  const hashRead = await fetch(base + '/rest/v1/users?select=password_hash&limit=1',
    { headers, signal: AbortSignal.timeout(30000) });
  if (hashRead.ok) throw new Error('Users table exposed password hashes');
  console.log('Profile and role: PASS');
  console.log(`Assigned role: ${profile.role}`);
  for (const path of [
    '/rest/v1/users?select=id,display_name,presence_status,last_active_at&limit=1',
    '/rest/v1/conversations?select=id&limit=1',
    '/rest/v1/messages?select=id&limit=1',
    '/rest/v1/conversation_participants?select=id&limit=1',
    '/rest/v1/notification_items?select=id&limit=1',
    '/rest/v1/file_attachments?select=id&limit=1',
    '/rest/v1/audit_logs?select=id&limit=1',
  ]) {
    await request(path);
    console.log(`${path.split('?')[0]}: PASS`);
  }
  for (const rpc of ['list_kryintalk_groups', 'get_conversation_state']) {
    await request(`/rest/v1/rpc/${rpc}`, {});
    console.log(`${rpc}: PASS`);
  }
  if (profile.is_super_admin || profile.role === 'admin') {
    for (const path of [
      '/rest/v1/users?select=id,email,username,display_name,is_active,is_suspended,role,organization_id&limit=1',
      '/rest/v1/roles?select=id,code&limit=1',
      '/rest/v1/user_roles?select=user_id,role_id&limit=1',
    ]) {
      await request(path);
      console.log(`Admin ${path.split('?')[0]}: PASS`);
    }
  }
} finally {
  await fetch(base + '/auth/v1/logout?scope=local', { method: 'POST', headers });
}
