import {test} from 'node:test';
import assert from 'node:assert/strict';
import {gameStatistics} from '../src/statistics.js';
const history=[{level:'easy',result:'won'},{level:'easy',result:'lost'},{level:'easy',result:'abandoned'},{level:'medium',result:'won'}];
test('results use current difficulty and exclude unfinished games from win-rate denominator',()=>{
 assert.deepEqual(gameStatistics(history,'easy'),{total:3,wins:1,finished:2,winRate:'50%'});
 assert.deepEqual(gameStatistics(history),{total:4,wins:2,finished:3,winRate:'67%'});
});
test('latest losses and wins immediately update result statistics',()=>{
 const afterLoss=[{level:'easy',result:'lost'},...history];
 assert.deepEqual(gameStatistics(afterLoss,'easy'),{total:4,wins:1,finished:3,winRate:'33%'});
 assert.deepEqual(gameStatistics([{level:'easy',result:'won'},...afterLoss],'easy'),{total:5,wins:2,finished:4,winRate:'50%'});
});
test('empty and unfinished histories have no win rate',()=>{
 assert.deepEqual(gameStatistics([]),{total:0,wins:0,finished:0,winRate:'—'});
 assert.deepEqual(gameStatistics([{level:'easy',result:'abandoned'}]),{total:1,wins:0,finished:0,winRate:'—'});
});

test('logical and classic statistics are independent and legacy records remain logical',()=>{
 const mixed=[...history,{level:'easy',mode:'classic',result:'won'}];
 assert.deepEqual(gameStatistics(mixed,'easy','logical'),{total:3,wins:1,finished:2,winRate:'50%'});
 assert.deepEqual(gameStatistics(mixed,'easy','classic'),{total:1,wins:1,finished:1,winRate:'100%'});
});
