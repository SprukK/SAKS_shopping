import React from 'react';import{createRoot}from'react-dom/client';import{HashRouter}from'react-router-dom';import{registerSW}from'virtual:pwa-register';import App from'./App';import'./styles.css';
registerSW({immediate:true});
createRoot(document.getElementById('root')!).render(<React.StrictMode><HashRouter><App/></HashRouter></React.StrictMode>);
