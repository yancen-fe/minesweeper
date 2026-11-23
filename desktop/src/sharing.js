import {Board,isSolvable} from './engine.js';
const levels=['easy','medium','hard'],modes=['classic','logical'];
const invalid=()=>{throw Error('分享码无效或不完整');};
function crc(bytes){let n=0xffffffff;for(const b of bytes){n^=b;for(let j=0;j<8;j++)n=(n>>>1)^((n&1)?0xedb88320:0);}return ((n^0xffffffff)>>>0).toString(16).padStart(8,'0').toUpperCase();}
function base64(bytes){return btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');}
function payload(board,mode,first,seconds,progress){
 if(!levels.includes(board.level)||!modes.includes(mode)||!Number.isInteger(first)||first<0||first>=board.cells.length||!Number.isInteger(seconds)||seconds<0||seconds>0xffffffff)invalid();
 const bytes=new Uint8Array(9+Math.ceil(board.cells.length/8)+(progress?Math.ceil(board.cells.length/4):0));
 bytes[0]=progress?1:0;bytes[1]=levels.indexOf(board.level);bytes[2]=modes.indexOf(mode);new DataView(bytes.buffer).setUint16(3,first);new DataView(bytes.buffer).setUint32(5,progress?seconds:0);
 board.cells.forEach((c,i)=>{if(c.mine)bytes[9+(i>>3)]|=1<<(i%8);if(progress)bytes[9+Math.ceil(board.cells.length/8)+(i>>2)]|=(c.open?1:c.mark===1?2:c.mark===2?3:0)<<((i%4)*2);});
 return bytes;
}
export function gameID(board,mode,first){let hash=0xcbf29ce484222325n;for(const b of payload(board,mode,first,0,false))hash=BigInt.asUintN(64,(hash^BigInt(b))*0x100000001b3n);return 'MS-'+hash.toString(16).padStart(16,'0').toUpperCase();}
export function encodeGame(board,mode,first,seconds=0,progress=false){
 if(board.phase==='ready'||(progress&&board.phase!=='playing'))throw Error(progress?'当前没有可继续的进度':'翻开第一格后即可分享本局');
 const bytes=payload(board,mode,first,seconds,progress);return `MS1.${base64(bytes)}.${crc(bytes)}`;
}
export function decodeGame(input){
 if(typeof input!=='string'||input.length>2048)invalid();const code=input.replace(/\s/g,''),parts=code.split('.');
 if(parts.length!==3||parts[0]!=='MS1'||!/^[A-Za-z0-9_-]+$/.test(parts[1])||!/^[A-Fa-f0-9]{8}$/.test(parts[2])||code.length>300)invalid();
 let bytes;try{bytes=Uint8Array.from(atob(parts[1].replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0));}catch{invalid();}
 if(base64(bytes)!==parts[1]||crc(bytes)!==parts[2].toUpperCase()||bytes.length<9||bytes[0]>1||bytes[1]>2||bytes[2]>1)invalid();
 const board=new Board(levels[bytes[1]]),mode=modes[bytes[2]],progress=bytes[0]===1,first=new DataView(bytes.buffer).getUint16(3),seconds=new DataView(bytes.buffer).getUint32(5),n=board.cells.length,mineBytes=Math.ceil(n/8),stateBytes=Math.ceil(n/4);
 if(bytes.length!==9+mineBytes+(progress?stateBytes:0)||first>=n||(!progress&&seconds!==0))invalid();
 for(let i=n;i<mineBytes*8;i++)if(bytes[9+(i>>3)]&(1<<(i%8)))invalid();
 if(progress)for(let i=n;i<stateBytes*4;i++)if((bytes[9+mineBytes+(i>>2)]>>((i%4)*2))&3)invalid();
 board.cells.forEach((c,i)=>{c.mine=!!(bytes[9+(i>>3)]&(1<<(i%8)));if(progress){const state=(bytes[9+mineBytes+(i>>2)]>>((i%4)*2))&3;c.open=state===1;c.mark=state===2?1:state===3?2:0;}});
 if(board.cells.filter(c=>c.mine).length!==board.mines||[first,...board.neighbors[first]].some(i=>board.cells[i].mine)||board.cells.some(c=>c.open&&c.mine))invalid();
 board.cells.forEach((c,i)=>c.n=board.neighbors[i].filter(j=>board.cells[j].mine).length);board.flags=board.cells.filter(c=>c.mark===1).length;board.opened=board.cells.filter(c=>c.open).length;board.phase='playing';
 if(progress&&(!board.cells[first].open||board.opened>=n-board.mines||board.flags>board.mines))invalid();
 if(mode==='logical'&&!isSolvable(board,first))throw Error('分享码中的雷区不符合无猜玩法');
 return {board,mode,first,seconds,progress,id:gameID(board,mode,first)};
}
export function restoreGame(shared,continueProgress){
 // Never mutate the preview: the same progress code can also start a fresh challenge.
 const board=new Board(shared.board.level);board.cells=shared.board.cells.map(c=>({...c,open:continueProgress?c.open:false,mark:continueProgress?c.mark:0}));board.phase='playing';board.opened=continueProgress?shared.board.opened:0;board.flags=continueProgress?shared.board.flags:0;
 if(continueProgress&&!shared.progress)throw Error('这份分享码只包含雷区');
 if(!continueProgress)board.reveal(shared.first);
 return {board,mode:shared.mode,first:shared.first,seconds:continueProgress?shared.seconds:0};
}
