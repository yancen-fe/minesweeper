import {invoke} from '@tauri-apps/api/core';
import {listen} from '@tauri-apps/api/event';
import {readLocal,localKey} from './local-storage.js';
import {createBrowserLibrary} from './browser-library.js';
const native=!!globalThis.window?.__TAURI_INTERNALS__;
export function applyLibraryOperation(current,operation,payload){
 const data=structuredClone(current);
 if(operation==='record'&&!data.history.some(r=>r.id===payload.id)){
  data.history.push(payload);
  if(payload.result==='won'){const key=payload.mode==='classic'?'classic:'+payload.level:payload.level;if(data.best[key]==null||payload.seconds<data.best[key])data.best[key]=payload.seconds;}
 }else if(operation==='clear'){data.history=[];data.best={};}
 else if(operation==='settings')Object.assign(data.settings,payload);
 data.history.sort((a,b)=>b.endedAt-a.endedAt||a.id.localeCompare(b.id));
 if(operation!=='load')data.revision++;
 return data;
}
export function createSharedStore({read,write,exclusive,onChange=()=>{}}){
 return async(operation,payload)=>exclusive(async()=>{const data=applyLibraryOperation(read(),operation,payload);if(operation!=='load')write(data);onChange(data);return data;});
}
function browserSnapshot(){const history=readLocal('history',[]),best=readLocal('best',{}),settings=readLocal('settings',{});return {revision:0,history:Array.isArray(history)?history:[],best:best&&typeof best==='object'?best:{},settings:settings&&typeof settings==='object'?settings:{}};}
const browserRequest=createBrowserLibrary(applyLibraryOperation);
export async function connectSharedStore(onChange){
 const channel=!native&&typeof BroadcastChannel!=='undefined'?new BroadcastChannel('minesweeper-web-library'):null;
 const request=async(operation,payload=null)=>{
  const data=native?await invoke('shared_data',{operation,payload}):await browserRequest(operation,payload);
  onChange(data);if(!native&&operation!=='load'){channel?.postMessage(data.revision);try{localStorage.setItem(localKey('library-revision'),String(data.revision));}catch{}}return data;
 };
 if(native)await listen('shared-data-changed',event=>onChange(event.payload));
 else{if(channel)channel.onmessage=()=>request('load').catch(console.error);window.addEventListener('storage',event=>{if(event.key===localKey('library-revision'))request('load').catch(console.error);});}
 await request('load',browserSnapshot());
 return request;
}
