import {invoke} from '@tauri-apps/api/core';
import {readLocal,writeLocal} from './local-storage.js';
import defaultAppIcon from '../src-tauri/icons/icon.png';
const native=!!window.__TAURI_INTERNALS__;
export const customIcons={};
export const iconImages={};
const key='custom-icons-v1';
export const validIconKind=kind=>['app','flag','mine'].includes(kind);
function cache(kind,url,onChange){
  customIcons[kind]=url;if(!native&&kind==='app')setFavicon(url);
  const image=new Image();
  image.onload=()=>{if(customIcons[kind]!==url)return;iconImages[kind]=image;onChange();};
  image.onerror=()=>{if(customIcons[kind]!==url)return;delete customIcons[kind];delete iconImages[kind];onChange();};
  image.src=url;
}
function setFavicon(url){let icon=document.querySelector('link[rel=icon]');if(!icon){icon=document.createElement('link');icon.rel='icon';document.head.append(icon);}icon.href=url||defaultAppIcon;}
function save(){writeLocal(key,customIcons);}
export async function loadIcons(onChange){
  try {
    const stored=native?await invoke('load_custom_icons'):readLocal(key,{});
    if(!native)setFavicon(stored.app);
    for(const kind of Object.keys(customIcons))if(!stored[kind]){delete customIcons[kind];delete iconImages[kind];onChange();}
    for(const [kind,url] of Object.entries(stored))if(validIconKind(kind)&&typeof url==='string'&&url.startsWith('data:image/png;base64,')&&url.length<3*1024*1024)cache(kind,url,onChange);
  }catch{}
}
function browserPick(){
  return new Promise(resolve=>{
    const input=document.createElement('input');input.type='file';input.accept='.png,.jpg,.jpeg,.ico';
    input.onchange=()=>resolve(input.files?.[0]??null);input.oncancel=()=>resolve(null);input.click();
  });
}
async function browserImage(file,kind){
  if(!file.size||file.size>8*1024*1024)throw new Error('请选择 8 MB 以内的 PNG、JPG 或 ICO 图片');
  const data=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=reject;reader.readAsDataURL(file);});
  const image=new Image();image.src=data;await image.decode();
  if(image.width>4096||image.height>4096)throw new Error('图片尺寸请控制在 4096 × 4096 以内');
  const size=kind==='app'?512:128,scale=size/Math.max(image.width,image.height),canvas=document.createElement('canvas');
  canvas.width=Math.max(1,Math.round(image.width*scale));canvas.height=Math.max(1,Math.round(image.height*scale));
  canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);return canvas.toDataURL('image/png');
}
export async function chooseIcon(kind,onChange){
  if(!validIconKind(kind))return;
  let url;
  if(native)url=await invoke('choose_custom_icon',{kind});
  else {const file=await browserPick();if(!file)return;url=await browserImage(file,kind);}
  if(!url)return;
  const previous=customIcons[kind];customIcons[kind]=url;
  if(!native)try{save();}catch(error){if(previous)customIcons[kind]=previous;else delete customIcons[kind];throw new Error('暂时无法保存图标');}
  cache(kind,url,onChange);
}
export async function resetIcon(kind,onChange){
  if(!validIconKind(kind))return;
  if(native)await invoke('reset_custom_icon',{kind});
  const previous=customIcons[kind];delete customIcons[kind];
  if(!native)try{save();}catch(error){customIcons[kind]=previous;throw new Error('暂时无法恢复图标');}
  delete iconImages[kind];if(!native&&kind==='app')setFavicon();onChange();
}
