import {readLocal,reportStorageError} from './local-storage.js';
let database;
function open(){
 if(!database)database=new Promise((resolve,reject)=>{
  const request=indexedDB.open('minesweeper-web-v1',1);
  request.onupgradeneeded=()=>request.result.createObjectStore('state');
  request.onsuccess=()=>{request.result.onversionchange=()=>{request.result.close();database=null;};resolve(request.result);};
  request.onerror=()=>{database=null;reject(request.error);};
 });
 return database;
}
function initial(){
 const history=readLocal('history',[]),best=readLocal('best',{}),settings=readLocal('settings',{});
 const data={revision:0,history:Array.isArray(history)?history:[],best:best&&typeof best==='object'?best:{},settings:settings&&typeof settings==='object'?settings:{}};
 // The original web edition stored only these app-specific classic best times.
 for(const level of ['easy','medium','hard'])try{
  const stored=localStorage.getItem(`yancen-minesweeper-${level}`),seconds=Number(stored);
  if(stored!==null&&Number.isSafeInteger(seconds)&&seconds>=0&&data.best['classic:'+level]==null)data.best['classic:'+level]=seconds;
 }catch{}
 return data;
}
let memory,queue=Promise.resolve();
export function createBrowserLibrary(apply){
 let unavailable=false;
 return async(operation,payload)=>{
  try{
   if(unavailable)throw Error('本地存储不可用');
   const db=await open();
   return await new Promise((resolve,reject)=>{
    const transaction=db.transaction('state','readwrite'),store=transaction.objectStore('state'),request=store.get('library');let result;
    request.onsuccess=()=>{try{result=apply(request.result??initial(),operation,payload);if(!request.result||operation!=='load')store.put(result,'library');}catch(error){transaction.abort();reject(error);}};
    transaction.oncomplete=()=>{memory=structuredClone(result);resolve(result);};
    transaction.onerror=()=>reject(transaction.error);transaction.onabort=()=>reject(transaction.error??Error('本地保存未完成'));
   });
  }catch{
   unavailable=true;reportStorageError();
   // Browsing remains possible if a privacy setting or storage quota blocks persistence.
   const pending=queue.catch(()=>{}).then(()=>{memory=apply(memory??initial(),operation,payload);return structuredClone(memory);});queue=pending;return pending;
  }
 };
}
