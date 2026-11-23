import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createSharedStore} from '../src/shared-store.js';
function library(){
 let data={revision:0,history:[],best:{easy:80},settings:{rounded:true,press:true}},tail=Promise.resolve();
 const exclusive=fn=>{const next=tail.then(fn);tail=next.catch(()=>{});return next;};
 const options={read:()=>structuredClone(data),write:value=>{data=structuredClone(value);},exclusive};
 return {one:createSharedStore(options),two:createSharedStore(options),get:()=>data};
}
const record=(id,seconds=30)=>({id,level:'easy',mode:'classic',result:'won',seconds,startedAt:1,endedAt:2});
test('concurrent windows merge records and choose the fastest best time without losing old bests',async()=>{
 const store=library();await Promise.all(Array.from({length:80},(_,i)=>(i%2?store.one:store.two)('record',record(String(i),80-i))));
 const data=store.get();assert.equal(data.history.length,80);assert.equal(data.best['classic:easy'],1);assert.equal(data.best.easy,80);assert.equal(data.revision,80);
 await store.two('record',record('1'));assert.equal(store.get().history.length,80,'close and pagehide cannot duplicate a session');
});
test('independent settings patches preserve other windows changes and clear is authoritative',async()=>{
 const store=library();await Promise.all([store.one('settings',{rounded:false}),store.two('settings',{mask:false}),store.one('record',record('one')),store.two('record',record('two'))]);
 assert.deepEqual(store.get().settings,{rounded:false,press:true,mask:false});await store.two('clear');assert.deepEqual(store.get().history,[]);assert.deepEqual(store.get().best,{});assert.equal(store.get().settings.press,true);
 await store.one('record',record('after-clear',7));assert.equal(store.get().history.length,1);
});
