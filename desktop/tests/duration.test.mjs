import {test} from 'node:test';
import assert from 'node:assert/strict';
import {formatDuration} from '../src/duration.js';
test('dialog durations omit zero minutes but preserve seconds and minute carry',()=>{
 for(const [seconds,text] of [[0,'0 秒'],[1,'1 秒'],[45,'45 秒'],[59,'59 秒'],[60,'1 分 00 秒'],[65,'1 分 05 秒'],[3599,'59 分 59 秒']])assert.equal(formatDuration(seconds),text);
});
