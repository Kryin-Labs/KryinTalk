// Local-only integration test. No production keys, tokens, or raw codes are printed.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const config=JSON.parse(readFileSync(process.argv[2]??'tools/account-access-test/status.json','utf8'));
const base=config.API_URL;
assert(['127.0.0.1','localhost'].includes(new URL(base).hostname),'Refusing non-local Supabase');
const key=config.PUBLISHABLE_KEY??config.ANON_KEY;
async function request(path,body,token){
 const response=await fetch(base+path,{method:'POST',
 headers:{apikey:key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},
 body:JSON.stringify(body)});
 const data=await response.json().catch(()=>null);
 assert(response.ok,'Local HTTP '+response.status+' ('+(data?.code??'request')+')');
 return data;
}
async function login(email){
 const result=await request('/auth/v1/token?grant_type=password',{email,password:'local-only-test-password'});
 assert(result.access_token);return result.access_token;
}
const admin=await login('actor4@example.test');
const actor=await login('actor1@example.test');
const invite=await request('/rest/v1/rpc/create_app_access_invite',{p_email:'actor1@example.test'},admin);
assert(invite.code?.length===48);
const results=await Promise.all([1,2].map(()=>request('/rest/v1/rpc/redeem_app_access_invite',{p_code:invite.code},actor)));
assert.equal(results.filter(r=>r.ok===true).length,1,'Exactly one concurrent redemption succeeds');
assert.equal(results.filter(r=>r.error_code==='invalid_code').length,1);
const profile=await request('/rest/v1/rpc/get_current_user_profile',{},actor);
assert.equal(profile.access_status,'approved');assert.equal(profile.role,'member');
const failures=await Promise.all(Array.from({length:7},()=>request('/rest/v1/rpc/redeem_app_access_invite',{p_code:'invalid'},actor)));
assert(failures.some(r=>r.error_code==='rate_limited'),'Concurrent failures hit server limit');
for(const token of [admin,actor])await request('/auth/v1/logout?scope=local',{},token);
console.log('PASS: one concurrent redemption, member-only approval, concurrent attempt rate limit, local logout.');

