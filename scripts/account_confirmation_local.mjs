// Disposable local signup/confirmation check. Never prints mail links or tokens.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const config=JSON.parse(readFileSync(process.argv[2]??'tools/account-access-test/status.json','utf8'));
const base=config.API_URL;
assert(['127.0.0.1','localhost'].includes(new URL(base).hostname),'Refusing non-local Supabase');
const key=config.PUBLISHABLE_KEY??config.ANON_KEY;
async function request(path,body,token){
 const r=await fetch(base+path,{method:'POST',headers:{apikey:key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
 return {ok:r.ok,status:r.status,data:await r.json().catch(()=>null)};
}
const username='onboarding_'+Date.now(),email=username+'@example.test',password='local-only-test-password';
const signup=await request('/auth/v1/signup?redirect_to='+encodeURIComponent('http://127.0.0.1:8080/auth/callback'),{email,password,data:{username,display_name:'Local confirmation test',agreement:true,policy_version:'2026-09-26'}});
assert(signup.ok,'Local signup HTTP '+signup.status+' ('+(signup.data.code??'unknown')+')');assert(!signup.data.access_token,'Signup does not authenticate');
const early=await request('/auth/v1/token?grant_type=password',{email,password});assert.equal(early.data.error_code??early.data.code,'email_not_confirmed');
let message;
for(let attempt=0;attempt<10&&!message;attempt++){
 const mail=await (await fetch('http://127.0.0.1:55324/api/v1/messages')).json();
 message=mail.messages.find(m=>m.To?.some(to=>to.Address===email));
 if(!message)await new Promise(r=>setTimeout(r,200));
}
assert(message,'Confirmation delivered to local Mailpit');
const mail=await (await fetch('http://127.0.0.1:55324/api/v1/message/'+message.ID)).json();
const link=[...(mail.HTML??'').matchAll(/href="([^"]+)"/g)].map(m=>m[1].replaceAll('&amp;','&')).find(u=>u.includes('/auth/v1/verify'));
assert(link,'Mail has a confirmation link');assert(['127.0.0.1','localhost'].includes(new URL(link).hostname));
const verification=await fetch(link,{redirect:'manual'}),location=new URL(verification.headers.get('location'));
assert.equal(location.origin,'http://127.0.0.1:8080');assert.equal(location.pathname,'/auth/callback');
const params=new URLSearchParams(location.hash.substring(1));assert.equal(params.get('type'),'signup');
assert(params.get('access_token'));await request('/auth/v1/logout?scope=local',{},params.get('access_token'));
const repeated=await fetch(link,{redirect:'manual'});assert(new URL(repeated.headers.get('location')).hash.includes('error='),'Reused link has safe recovery');
const login=await request('/auth/v1/token?grant_type=password',{email,password});assert(login.ok);const token=login.data.access_token;
const profile=(await request('/rest/v1/rpc/get_current_user_profile',{},token)).data;
assert.equal(profile.email_confirmed,true);assert.equal(profile.access_status,'pending');assert.equal(profile.app_access,false);assert.deepEqual(profile.roles,[]);
for(const table of ['users','messages','file_attachments','notification_items']){
 const r=await fetch(base+'/rest/v1/'+table+'?select=id&limit=1',{headers:{apikey:key,Authorization:'Bearer '+token}});assert(r.ok);assert.deepEqual(await r.json(),[]);
}
await request('/auth/v1/logout?scope=local',{},token);
console.log('PASS: local signup, Mailpit confirmation, exact callback, reused-link recovery, explicit login, pending profile and direct data denials.');
