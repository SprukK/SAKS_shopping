import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';
export default defineConfig(({mode})=>({base:mode==='production'?'/SAKS_shopping/':'/',plugins:[react(),VitePWA({registerType:'autoUpdate',includeAssets:['icon.svg'],manifest:{name:'SAKS Nakupovanje',short_name:'SAKS',description:'Skupno načrtovanje obrokov in nakupov za plovbo',theme_color:'#073b4c',background_color:'#f4f1e8',display:'standalone',start_url:'./',icons:[{src:'icon.svg',sizes:'any',type:'image/svg+xml',purpose:'any maskable'}]},workbox:{navigateFallback:'index.html'}})]}));
