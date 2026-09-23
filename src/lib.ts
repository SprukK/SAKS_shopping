import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_ANON_KEY;
export const configured=Boolean(url&&key);
export const supabase=createClient(url||'https://placeholder.supabase.co',key||'placeholder',{auth:{persistSession:true,autoRefreshToken:true}});
export const rememberName=(name:string)=>localStorage.setItem('saks-display-name',name);
export const savedName=()=>localStorage.getItem('saks-display-name')||'';
export async function ensureAuth(){const {data}=await supabase.auth.getSession();if(data.session)return data.session.user;const {data:created,error}=await supabase.auth.signInAnonymously();if(error)throw error;return created.user!}
export const tripKey=(token:string)=>`saks-participant-${token}`;
