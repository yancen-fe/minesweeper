import {LogicalSize} from '@tauri-apps/api/window';

export function windowSizeForLevel(level){
 const sizes={easy:{width:430,height:550},medium:{width:550,height:650},hard:{width:960,height:650}};
 return {...(sizes[level]||sizes.easy)};
}

export function createWindowResizer(appWindow,{
 readSize=()=>({width:innerWidth,height:innerHeight}),
 reducedMotion=()=>matchMedia('(prefers-reduced-motion: reduce)').matches,
 nextFrame=()=>new Promise(resolve=>requestAnimationFrame(resolve)),
 now=()=>performance.now(),
 duration=240
}={}){
 let revision=0,pending=Promise.resolve();
 return target=>{
  const token=++revision;
  // Serialize native calls so an interrupted transition cannot overwrite the latest size.
  pending=pending.catch(()=>{}).then(async()=>{
   if(token!==revision)return;
   const from=readSize();
   // Raising the minimum first would snap an expanding window straight to that size.
   await appWindow.setMinSize(new LogicalSize(Math.min(from.width,target.width),Math.min(from.height,target.height)));
   if(token!==revision)return;
   await appWindow.setMaxSize(undefined);
   if(token!==revision)return;
   const start=now(),animate=target.animate!==false&&duration>0&&!reducedMotion();
   let previous='';
   do{
    if(animate)await nextFrame();
    if(token!==revision)return;
    const progress=animate?Math.min(1,Math.max(0,(now()-start)/duration)):1;
    const ease=1-(1-progress)**3;
    const width=Math.round(from.width+(target.width-from.width)*ease),height=Math.round(from.height+(target.height-from.height)*ease);
    const size=`${width},${height}`;
    if(size!==previous){await appWindow.setSize(new LogicalSize(width,height));previous=size;}
    if(token!==revision)return;
    if(progress===1)break;
   }while(true);
   await appWindow.setMinSize(new LogicalSize(target.width,target.height));
   if(token!==revision)return;
   await appWindow.setMaxSize(new LogicalSize(target.width,target.height));
  });
  return pending;
 };
}
