import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWindowResizer,windowSizeForLevel} from '../src/window-resize.js';

const easy=windowSizeForLevel('easy');
const hard=windowSizeForLevel('hard');
function setup(options={}){
 let size={width:430,height:550},clock=0;
 const sizes=[],minimums=[],maximums=[];
 const appWindow={
  async setSize(value){size={width:value.width,height:value.height};sizes.push({...size});},
  async setMinSize(value){minimums.push({width:value.width,height:value.height});},
  async setMaxSize(value){maximums.push(value?{width:value.width,height:value.height}:null);}
 };
 const resize=createWindowResizer(appWindow,{readSize:()=>size,now:()=>clock,nextFrame:async()=>{clock+=16;},reducedMotion:()=>false,...options});
 return {resize,sizes,minimums,maximums};
}
test('difficulty resize animates smoothly to the exact target before raising the minimum',async()=>{
 const {resize,sizes,minimums,maximums}=setup();
 await resize(hard);
 assert.ok(sizes.length>5);
 assert.ok(sizes[0].width>430&&sizes[0].width<632);
 assert.deepEqual(sizes.at(-1),{width:960,height:650});
 assert.ok(sizes.every((s,i)=>i===0||s.width>=sizes[i-1].width));
 assert.deepEqual(minimums[0],{width:430,height:550});
 assert.equal(maximums[0],null);
 assert.deepEqual(minimums.at(-1),hard);
 assert.deepEqual(maximums.at(-1),hard);
});
test('a new difficulty cancels an in-flight transition and finishes at the newest target',async()=>{
 const {resize,sizes,minimums,maximums}=setup();
 const first=resize(hard);
 for(let i=0;i<20&&sizes.length===0;i++)await Promise.resolve();
 assert.ok(sizes.length>0&&sizes.at(-1).width<960,'interrupt after the window starts moving');
 const second=resize(easy);
 await Promise.all([first,second]);
 assert.deepEqual(sizes.at(-1),{width:430,height:550});
 assert.deepEqual(minimums.at(-1),easy);
 assert.deepEqual(maximums.at(-1),easy);
});
test('reduced motion skips intermediate window sizes',async()=>{
 const {resize,sizes}=setup({reducedMotion:()=>true});
 await resize(hard);
 assert.deepEqual(sizes,[{width:960,height:650}]);
});
test('a failed native resize does not block the next difficulty change',async()=>{
 let fail=true;
 const sizes=[];
 const resize=createWindowResizer({async setMinSize(){},async setMaxSize(){},async setSize(s){if(fail)throw new Error('resize failed');sizes.push(s.width);}},{readSize:()=>easy,reducedMotion:()=>true});
 await assert.rejects(resize(hard),/resize failed/);
 fail=false;
 await resize(easy);
 assert.deepEqual(sizes,[430]);
});

test('restoring the saved difficulty at startup applies its fixed size without animation',async()=>{
 const {resize,sizes,minimums,maximums}=setup();
 await resize({...windowSizeForLevel('medium'),animate:false});
 assert.deepEqual(sizes,[{width:550,height:650}]);
 assert.deepEqual(minimums.at(-1),{width:550,height:650});
 assert.deepEqual(maximums.at(-1),{width:550,height:650});
});

test('native configuration disables manual resize and maximize and fixes initial bounds',async()=>{
 const {readFile}=await import('node:fs/promises');
 const config=JSON.parse(await readFile(new URL('../src-tauri/tauri.conf.json',import.meta.url),'utf8'));
 const window=config.app.windows[0];
 assert.equal(window.resizable,false);assert.equal(window.maximizable,false);
 assert.equal(window.minWidth,window.width);assert.equal(window.maxWidth,window.width);
 assert.equal(window.minHeight,window.height);assert.equal(window.maxHeight,window.height);
});
