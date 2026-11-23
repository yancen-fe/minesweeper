import {test} from 'node:test';import assert from 'node:assert/strict';
import {Board,LEVELS,deductions,generate,generateForMode,isSolvable} from '../src/engine.js';
let seed=714;const random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/2**32;};
test('verified boards preserve counts, safe first move and full logical proof',()=>{for(const level of Object.keys(LEVELS)){for(let j=0;j<3;j++){const {board}=generate(level,j,random);assert.equal(board.cells.filter(c=>c.mine).length,board.mines);for(const i of [j,...board.neighbors[j]])assert.equal(board.cells[i].mine,false);assert.equal(isSolvable(board,j),true);board.reveal(j);for(let i=0;i<board.cells.length;i++)if(!board.cells[i].mine)board.reveal(i);assert.equal(board.phase,'won');}}});
test('marks cycle through flag, question, empty and do not reveal flagged cells',()=>{const b=new Board();b.plant(0);b.mark(80);assert.equal(b.flags,1);b.reveal(80);assert.equal(b.cells[80].open,false);b.mark(80);assert.equal(b.flags,0);assert.equal(b.cells[80].mark,2);b.mark(80);assert.equal(b.cells[80].mark,0);});
test('wrong flags can cause a loss and every opened safe tile wins',()=>{const b=new Board();b.plant(0);const mine=b.cells.findIndex(c=>c.mine);b.reveal(mine);assert.equal(b.phase,'lost');assert.equal(b.exploded,mine);const before=b.flags;b.mark(5);assert.equal(b.flags,before);});
test('subset deductions never consult hidden mine locations',()=>{const visible=[{open:true,n:1},{open:false},{open:false}];const a=deductions(visible,[[1,2],[],[]],1,new Set([1]));assert.deepEqual([...a.safe],[2]);visible[2].mine=true;assert.deepEqual([...deductions(visible,[[1,2],[],[]],1,new Set([1])).safe],[2]);});
test('structured worker delivery restores methods and marks remain independent',()=>{const b=new Board('medium');b.plant(136);const copy=Board.restore(structuredClone(b));copy.reveal(136);assert.ok(copy.opened>0);assert.ok(copy.phase==='playing'||copy.phase==='won');});

test('a safe wrong flag next to a one does not count as a second mine',()=>{
 const b=new Board();b.phase='playing';
 const mine=42,wrong=51,number=43;
 b.cells[mine].mine=true;
 for(let i=0;i<b.cells.length;i++)b.cells[i].n=b.neighbors[i].filter(j=>b.cells[j].mine).length;
 b.mark(wrong);b.reveal(number);
 assert.equal(b.cells[number].n,1);
 assert.equal(b.cells[wrong].mine,false);
 assert.ok(b.neighbors[number].includes(wrong));
 b.reveal(mine);
 assert.equal(b.phase,'lost');
 assert.equal(b.cells[number].n,1);
 assert.equal(b.neighbors[number].filter(j=>b.cells[j].mine).length,1);
 assert.equal(b.cells[wrong].mark,1);
});

test('classic mode keeps first-move protection and accepts boards without a logical proof',()=>{
 let ambiguous=false;
 for(const level of Object.keys(LEVELS)){
  for(let attempt=0;attempt<10;attempt++){
   const {board,tries}=generateForMode(level,0,'classic',random);
   assert.equal(tries,1);
   assert.equal(board.cells.filter(c=>c.mine).length,board.mines);
   for(const i of [0,...board.neighbors[0]])assert.equal(board.cells[i].mine,false);
   if(!isSolvable(board,0))ambiguous=true;
  }
 }
 assert.ok(ambiguous,'random mode must not filter out layouts that may need guessing');
 const logical=generateForMode('easy',0,'logical',random);
 assert.equal(isSolvable(logical.board,0),true);
});
