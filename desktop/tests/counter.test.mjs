import {test} from 'node:test';
import assert from 'node:assert/strict';
import {counterMarkup,setCounter,setTimerCounter} from '../src/counter.js';

test('seven-segment counters pad zeroes and draw the expected lit segments',()=>{
 const zero=counterMarkup(0);
 assert.equal((zero.match(/fill="#ff1008"/g)||[]).length,18);
 assert.equal((counterMarkup(123).match(/fill="#ff1008"/g)||[]).length,12);
 assert.match(zero,/aria-hidden="true"/);
});
test('remaining mine counters support negative and long values without clipping',()=>{
 const negative=counterMarkup(-1);
 assert.equal((negative.match(/fill="#ff1008"/g)||[]).length,9);
 assert.equal((negative.split('</g>')[0].match(/fill="#ff1008"/g)||[]).length,1,'minus sign is the first digit');
 assert.match(counterMarkup(-381),/viewBox="0 0 76 32"/);
 assert.equal(counterMarkup(Infinity),counterMarkup(0));
});
test('unchanged counter values preserve the displayed SVG',()=>{
 let writes=0;
 const element={dataset:{},set innerHTML(value){writes++;assert.match(value,/<svg/);}};
 setCounter(element,5);setCounter(element,5);
 assert.equal(writes,1);
 setCounter(element,6);
 assert.equal(writes,2);
});

test('timer stays numeric in seconds while dialog durations use minutes',()=>{
 const element={dataset:{},innerHTML:'',setAttribute(name,value){this[name]=value;}};
 for(const [seconds,value,digits] of [[0,0,3],[45,45,3],[65,65,3],[999,999,3],[1000,1000,4],[10000,10000,5],[100000,99999,5],[0,0,3]]){
  setTimerCounter(element,seconds);
  assert.equal(element.dataset.value,String(value));
  assert.equal(element.dataset.digits,String(digits));
  assert.match(element.innerHTML,new RegExp(`viewBox="0 0 ${digits*18+4} 32"`));
  assert.equal(element.innerHTML.includes('<circle'),false,'numeric timer has no colon');
  assert.equal(element['aria-label'],seconds<60?`用时 ${seconds} 秒`:`用时 ${Math.floor(seconds/60)} 分 ${String(seconds%60).padStart(2,'0')} 秒`);
 }
});
