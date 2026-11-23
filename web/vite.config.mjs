import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {readdir,writeFile} from 'node:fs/promises';
const root=fileURLToPath(new URL('.',import.meta.url));
export default {
 root,base:'./',server:{host:'127.0.0.1',port:5173,strictPort:true,fs:{allow:[root,resolve(root,'../desktop')]}},preview:{host:'127.0.0.1',port:5173,strictPort:true},
 plugins:[{name:'local-offline-shell',async closeBundle(){
  async function files(dir,prefix=''){const entries=await readdir(dir,{withFileTypes:true});return (await Promise.all(entries.map(e=>e.isDirectory()?files(resolve(dir,e.name),prefix+e.name+'/'):prefix+e.name))).flat();}
  const output=resolve(root,'dist');let assets;try{assets=await files(output);}catch{return;}
  assets=assets.filter(path=>path!=='sw.js');
  const version=JSON.stringify('minesweeper-shell-'+Date.now());
  await writeFile(resolve(output,'sw.js'),`const PREFIX='minesweeper-shell:'+self.registration.scope+':';const CACHE=PREFIX+${version};\nconst ASSETS=${JSON.stringify(assets.map(x=>'./'+x))};\nself.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS))));\nself.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith(PREFIX)&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));\nself.addEventListener('fetch',event=>{const url=new URL(event.request.url);if(event.request.method!=='GET'||url.origin!==self.location.origin)return;const known=ASSETS.some(asset=>new URL(asset,self.registration.scope).href===url.href);if(event.request.mode==='navigate'&&url.pathname.startsWith(new URL(self.registration.scope).pathname)){event.respondWith(fetch(event.request).catch(()=>caches.match(new URL('./index.html',self.registration.scope))));}else if(known){event.respondWith(caches.open(CACHE).then(cache=>cache.match(event.request,{ignoreVary:true})).then(hit=>hit||fetch(event.request)));}});\n`);
 }}]
};
