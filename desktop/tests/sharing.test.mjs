import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {Board} from '../src/engine.js';
import {decodeGame,encodeGame,gameID,restoreGame} from '../src/sharing.js';
const fixtures=JSON.parse(fs.readFileSync(new URL('../../tests/fixtures/share-v1.json',import.meta.url)));
const indices=(board,key)=>board.cells.flatMap((c,i)=>c[key]?[i]:[]);
function recode(bytes){let n=0xffffffff;for(const b of bytes){n^=b;for(let i=0;i<8;i++)n=(n>>>1)^((n&1)?0xedb88320:0);}return `MS1.${Buffer.from(bytes).toString('base64url')}.${((n^0xffffffff)>>>0).toString(16).padStart(8,'0')}`;}
for(const fixture of fixtures){
 test(`${fixture.level}/${fixture.mode} shares an identical cross-platform challenge and complete progress`,()=>{
  const shared=decodeGame(fixture.progress);assert.equal(shared.id,fixture.id);assert.equal(shared.first,fixture.first);assert.equal(shared.mode,fixture.mode);assert.equal(shared.seconds,fixture.seconds);
  assert.deepEqual(indices(shared.board,'mine'),fixture.mines);assert.deepEqual(indices(shared.board,'open'),fixture.opened);
  assert.deepEqual(shared.board.cells.flatMap((c,i)=>c.mark===1?[i]:[]),fixture.flags);assert.deepEqual(shared.board.cells.flatMap((c,i)=>c.mark===2?[i]:[]),fixture.questions);
  assert.equal(encodeGame(shared.board,shared.mode,shared.first,shared.seconds,true),fixture.progress);assert.equal(encodeGame(shared.board,shared.mode,shared.first,shared.seconds,false),fixture.challenge);
  const continued=restoreGame(shared,true),fresh=restoreGame(shared,false);assert.equal(continued.seconds,fixture.seconds);assert.equal(fresh.seconds,0);assert.equal(fresh.board.flags,0);assert.ok(fresh.board.cells[fixture.first].open);assert.equal(gameID(fresh.board,fixture.mode,fixture.first),fixture.id);
  const challenge=decodeGame(fixture.challenge);assert.equal(challenge.id,fixture.id);assert.equal(challenge.board.opened,0);assert.throws(()=>restoreGame(challenge,true));
  const before=shared.board.opened,safe=continued.board.cells.findIndex(c=>!c.mine&&!c.open&&!c.mark);if(safe>=0)continued.board.reveal(safe);assert.equal(shared.board.opened,before,'playing an import cannot change its preview');
  assert.equal(decodeGame(' \n'+fixture.progress+'\n ').id,fixture.id);assert.ok(fixture.progress.length<300);
 });
}
test('invalid, damaged, oversized and unsupported codes are rejected',()=>{
 const code=fixtures[0].progress;
 for(const value of ['',null,'MS2.'+code.split('.').slice(1).join('.'),code.slice(0,-1),code.slice(0,-1)+(code.endsWith('0')?'1':'0'),'x'.repeat(3000),code+'.extra',code.replace('MS1.','MS1.!')])assert.throws(()=>decodeGame(value));
});
test('even correctly checksummed data must satisfy board and progress invariants',()=>{
 const source=Buffer.from(fixtures[0].progress.split('.')[1],'base64url');
 const reject=mutate=>{const bytes=Buffer.from(source);mutate(bytes);assert.throws(()=>decodeGame(recode(bytes)));};
 reject(b=>b[1]=3);reject(b=>b[2]=2);reject(b=>b.writeUInt16BE(65535,3));reject(b=>b[9]^=1);reject(b=>b[19]|=128);reject(b=>b[b.length-1]|=128);
 reject(b=>{const i=fixtures[0].mines[0],j=9+11+(i>>2),shift=i%4*2;b[j]=(b[j]&~(3<<shift))|(1<<shift);});
 const challenge=Buffer.from(fixtures[0].challenge.split('.')[1],'base64url');challenge.writeUInt32BE(65,5);assert.throws(()=>decodeGame(recode(challenge)));

});
test('unstarted and ended progress cannot be shared, but ended layouts remain replayable',()=>{
 assert.throws(()=>encodeGame(new Board(),'classic',null));
 const shared=decodeGame(fixtures[0].progress),board=restoreGame(shared,true).board;board.reveal(fixtures[0].mines[0]);assert.equal(board.phase,'lost');assert.throws(()=>encodeGame(board,shared.mode,shared.first,65,true));assert.equal(decodeGame(encodeGame(board,shared.mode,shared.first)).id,shared.id);
});

test('both platforms reject the same semantically invalid codes even with valid checksums',()=>{
 const invalid=JSON.parse(fs.readFileSync(new URL('../../tests/fixtures/share-v1-invalid.json',import.meta.url)));
 for(const sample of invalid)assert.throws(()=>decodeGame(sample.code),sample.reason);
});
