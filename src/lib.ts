import {createClient} from '@supabase/supabase-js';
const url=(import.meta.env.VITE_SUPABASE_URL||'').trim();
const key=(import.meta.env.VITE_SUPABASE_ANON_KEY||'').trim();
const validUrl=/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(url);
export const configured=Boolean(validUrl&&key);
export const supabase=createClient(configured?url:'https://placeholder.supabase.co',configured?key:'placeholder',{auth:{persistSession:true,autoRefreshToken:true}});
export const rememberName=(name:string)=>localStorage.setItem('saks-display-name',name);
export const savedName=()=>localStorage.getItem('saks-display-name')||'';
export async function ensureAuth(){const {data}=await supabase.auth.getSession();if(data.session)return data.session.user;const {data:created,error}=await supabase.auth.signInAnonymously();if(error)throw error;return created.user!}
export const tripKey=(token:string)=>`saks-participant-${token}`;
