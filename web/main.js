import {setBrowserMarkMode} from '../desktop/src/main.js';
import './style.css';
const mark=document.querySelector('#mark-mode');
mark.addEventListener('click',()=>{const active=mark.getAttribute('aria-pressed')!=='true';mark.setAttribute('aria-pressed',String(active));setBrowserMarkMode(active);});
window.addEventListener('minesweeper-storage-error',()=>{const status=document.querySelector('#storage-status');status.hidden=false;status.textContent='本地存储不可用，刷新前请复制进度码';});
if(import.meta.env.PROD&&'serviceWorker' in navigator)window.addEventListener('load',()=>navigator.serviceWorker.register(new URL('./sw.js',location.href),{scope:'./'}).catch(()=>{}));
