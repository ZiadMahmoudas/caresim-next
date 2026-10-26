import { createClient } from '@supabase/supabase-js';

const [emailArg,password,fullName='CareSim Admin']=process.argv.slice(2);
const email=(emailArg||'').trim().toLowerCase();
const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
const secret=process.env.SUPABASE_SECRET_KEY;

if(!email||!password){
  console.error('Usage: npm run create-admin -- admin@example.com "StrongPassword123!" "Admin Name"');
  process.exit(1);
}
if(password.length<8){
  console.error('Password must be at least 8 characters.');
  process.exit(1);
}
if(!url||!secret){
  console.error('NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SECRET_KEY are required in .env.local');
  process.exit(1);
}

const supabase=createClient(url,secret,{auth:{autoRefreshToken:false,persistSession:false}});

let user=null;
let page=1;
while(!user){
  const {data,error}=await supabase.auth.admin.listUsers({page,perPage:1000});
  if(error){console.error('Could not list users:',error.message);process.exit(1)}
  user=data.users.find(u=>(u.email||'').toLowerCase()===email)||null;
  if(user||data.users.length<1000)break;
  page+=1;
}

if(user){
  const {data,error}=await supabase.auth.admin.updateUserById(user.id,{
    password,
    email_confirm:true,
    user_metadata:{...(user.user_metadata||{}),full_name:fullName,learner_type:'nurse'}
  });
  if(error){console.error('Could not update existing auth user:',error.message);process.exit(1)}
  user=data.user;
  console.log(`Existing auth user updated: ${email}`);
}else{
  const {data,error}=await supabase.auth.admin.createUser({
    email,password,email_confirm:true,user_metadata:{full_name:fullName,learner_type:'nurse'}
  });
  if(error){console.error('Could not create admin auth user:',error.message);process.exit(1)}
  user=data.user;
  console.log(`Auth user created: ${email}`);
}

const {error:profileError}=await supabase.from('profiles').upsert({
  id:user.id,
  email,
  full_name:fullName,
  role:'admin',
  learner_type:'nurse',
  updated_at:new Date().toISOString()
},{onConflict:'id'});

if(profileError){
  console.error('Auth user is ready, but profile/admin role update failed:',profileError.message);
  process.exit(1);
}

console.log('✅ CareSim admin is ready.');
console.log(`Email: ${email}`);
console.log('Password: the password you just supplied to this command.');
console.log('Open /login and sign in with those credentials.');
