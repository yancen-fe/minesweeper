import test from 'node:test';
import assert from 'node:assert/strict';
import {filterHistory} from '../src/history-filter.js';
import {gameStatistics} from '../src/statistics.js';
const now=new Date(2026,10,3,12),day=(offset,hour=12)=>new Date(2026,10,3+offset,hour).getTime();
const rows=[
 {id:'a',level:'easy',mode:'classic',result:'won',seconds:65,endedAt:day(0,0)},
 {id:'b',level:'hard',mode:'classic',result:'lost',seconds:12,endedAt:day(-6,0)},
 {id:'c',level:'easy',result:'won',seconds:90,endedAt:day(-7)},
 {id:'d',level:'medium',mode:'logical',result:'abandoned',seconds:0,endedAt:day(-29,0)},
 {id:'e',level:'easy',mode:'classic',result:'lost',seconds:80,endedAt:day(-30)},
 {id:'f',level:'easy',mode:'classic',result:'won',seconds:1,endedAt:day(1,0)}
];
test('history combines difficulty, legacy mode, result and date without mutating stored records',()=>{
 const original=structuredClone(rows);
 assert.deepEqual(filterHistory(rows,{level:'easy',mode:'classic',result:'won',range:'today'},now).map(r=>r.id),['a']);
 assert.deepEqual(filterHistory(rows,{mode:'logical',result:'won'},now).map(r=>r.id),['c']);
 assert.deepEqual(rows,original);
});
test('local calendar date ranges include their first midnight and exclude tomorrow',()=>{
 assert.deepEqual(filterHistory(rows,{range:'today'},now).map(r=>r.id),['a']);
 assert.deepEqual(filterHistory(rows,{range:'7'},now).map(r=>r.id),['a','b']);
 assert.deepEqual(filterHistory(rows,{range:'30'},now).map(r=>r.id),['a','b','c','d']);
});
test('all four sorts are deterministic and handle zero duration with stable ties',()=>{
 assert.deepEqual(filterHistory(rows,{order:'oldest'},now).map(r=>r.id),['e','d','c','b','a','f']);
 assert.deepEqual(filterHistory(rows,{order:'fastest'},now).map(r=>r.id),['d','f','b','a','e','c']);
 assert.deepEqual(filterHistory(rows,{order:'slowest'},now).map(r=>r.id),['c','e','a','b','f','d']);
 const ties=[{...rows[0],id:'z'},{...rows[0],id:'a'}];assert.deepEqual(filterHistory(ties).map(r=>r.id),['a','z']);
});
test('statistics use the filtered subset and an empty combination has no win rate',()=>{
 const subset=filterHistory(rows,{range:'7'},now);assert.deepEqual(gameStatistics(subset),{total:2,wins:1,finished:2,winRate:'50%'});
 const empty=filterHistory(rows,{level:'hard',result:'won'},now);assert.equal(empty.length,0);assert.equal(gameStatistics(empty).winRate,'—');
});
