import './style.css';
import {setCounter,setTimerCounter} from './counter.js';
import {formatDuration} from './duration.js';
import {connectSharedStore} from './shared-store.js';
import {readLocal,writeLocal,localKey,reportStorageError} from './local-storage.js';
import {invoke} from '@tauri-apps/api/core';
import {encodeGame,decodeGame,restoreGame,gameID} from './sharing.js';
import {filterHistory,historyResults,historyRanges,historyOrders} from './history-filter.js';
import {gameStatistics} from './statistics.js';
import {dropdown,bindDropdowns,closeDropdown} from './dropdown.js';
import '@fontsource/nunito/latin-800.css';
import '@fontsource/fredoka/latin-600.css';
import {customIcons,iconImages,loadIcons,chooseIcon,resetIcon} from './icons.js';
import defaultAppIcon from '../src-tauri/icons/icon.png';
import {Board,LEVELS} from './engine.js';
import {getCurrentWindow} from '@tauri-apps/api/window';
import {writeText as writeClipboard} from '@tauri-apps/plugin-clipboard-manager';
import {createWindowResizer,windowSizeForLevel} from './window-resize.js';
const native=!!window.__TAURI_INTERNALS__, names={easy:'初级',medium:'中级',hard:'专家'};
const modeNames={classic:'经典随机',logical:'无猜'};
const transitionWindow=native?createWindowResizer(getCurrentWindow()):null;
const load=readLocal;
const save=(key,value)=>{try{writeLocal(key,value);}catch{if(!native)reportStorageError();}};
const browserGame=!native&&document.documentElement.classList.contains('browser-game');
let touchPress=null;let browserMarkMode=false;export function setBrowserMarkMode(active){browserMarkMode=Boolean(active);}
const defaults={press:true,rounded:true,triangle:true,small:true,mask:true,result:true};
let prefs={...defaults,...load('settings',{})}, history=load('history',[]),best=load('best',{}),level=load('level','easy'),mode=load('mode','classic');
const windowOptions=new URLSearchParams(native?location.search:location.hash.slice(1)||location.search);if(LEVELS[windowOptions.get('level')])level=windowOptions.get('level');if(modeNames[windowOptions.get('mode')])mode=windowOptions.get('mode');
if(!LEVELS[level])level='easy';if(!modeNames[mode])mode='classic';if(!Array.isArray(history))history=[];
let firstMove=null,shareCode='',shareMessage='',importCode='',importPreview=null,importMessage='';
let board,paused=false,generating=false,worker=null,generation=0,elapsed=0,start=null,session=null,recorded=false,modal='',filter='all',modeFilter='all',resultFilter='all',dateFilter='all',historyOrder='newest',confirmReset=false,pressed=-1,dragging=false,focus=0;
let lastSecond=-1,settingsTab='game',iconBusy=false,iconMessage='';
const app=document.querySelector('#app');
app.innerHTML=`<main><header><nav aria-label="难度">${dropdown('level-select','难度',level,Object.entries(names).map(([value,title])=>({value,title})))}</nav><nav aria-label="玩法">${dropdown('mode-select','玩法',mode,Object.entries(modeNames).map(([value,title])=>({value,title})))}</nav><span class="spacer"></span><button id="pause">暂停</button><div class="menu-wrap"><button id="menu-toggle" aria-label="菜单" aria-haspopup="menu" aria-expanded="false">•••</button><div id="top-menu" role="menu" hidden><button role="menuitem" data-menu="new">新一局</button><button role="menuitem" data-menu="window">新建窗口</button><hr><button role="menuitem" data-menu="share">分享本局</button><button role="menuitem" data-menu="import">导入对局</button><hr><button role="menuitem" data-menu="history">历史记录</button><button role="menuitem" data-menu="settings">设置</button></div></div></header><section class="instruments bevel-in"><output id="remaining" aria-label="剩余雷数"></output><button id="restart" aria-label="新一局"><svg viewBox="0 0 32 32"><circle cx="16" cy="16" r="14" fill="#ffdc24" stroke="#171717" stroke-width="1.7"/><g id="face-eyes"><circle cx="11" cy="12" r="1.6"/><circle cx="21" cy="12" r="1.6"/></g><path id="face-mouth" d="M8 19 Q16 29 24 19" fill="none" stroke="#171717" stroke-width="1.7" stroke-linecap="round"/></svg></button><output id="timer" aria-label="用时"></output></section><div class="board-area"><section class="board-wrap bevel-in"><canvas id="board" tabindex="0" role="application" aria-label="扫雷棋盘"></canvas><div id="pause-mask" hidden><div class="pause-card"><button id="resume">▶ 继续游戏</button></div></div></section></div></main><div id="modal" hidden></div>`;
const $=s=>document.querySelector(s),canvas=$('#board'),ctx=canvas.getContext('2d');let tile=28,tileWidth=28,tileHeight=28,canvasWidth=0,canvasHeight=0;
const ended=()=>board.ended;
const seconds=()=>Math.floor((elapsed+(start===null?0:performance.now()-start))/1000);
function stopClock(){if(start!==null)elapsed+=performance.now()-start;start=null;}
function pause(){if(board.phase==='playing'||generating){stopClock();paused=true;render();}}
function resume(){if(modal||!paused)return;paused=false;if(board.phase==='playing'&&!generating)start=performance.now();render();}
const bestKey=()=>mode==='classic'?'classic:'+level:level;
function chooseMode(next){if(next===mode)return;restart();mode=next;save('mode',mode);render();}
let libraryRevision=-1,pendingRecords=new Map();
const libraryReady=connectSharedStore(data=>{
 if(data.revision<libraryRevision)return;libraryRevision=data.revision;
 history=[...data.history];for(const record of pendingRecords.values())if(!history.some(r=>r.id===record.id))history.unshift(record);
 best={...data.best};prefs={...defaults,...data.settings};
 if(native)for(const key of ['history','best','settings'])save(key,key==='history'?history:key==='best'?best:prefs);
 if(board){render();if(['history','settings'].includes(modal))paintModal();}
});
let pendingWrites=Promise.resolve();
function persist(operation,payload){
 const next=pendingWrites.catch(()=>{}).then(async()=>{const request=await libraryReady;return request(operation,payload);});
 pendingWrites=next;next.catch(console.error);return next;
}
function record(result){
 if(!session||recorded)return pendingWrites;stopClock();recorded=true;
 const entry={id:session.id,level,mode,startedAt:session.startedAt,endedAt:Date.now(),seconds:seconds(),result};
 pendingRecords.set(entry.id,entry);history.unshift(entry);
 if(result==='won'&&(best[bestKey()]==null||entry.seconds<best[bestKey()]))best[bestKey()]=entry.seconds;
 const writing=persist('record',entry).then(()=>{pendingRecords.delete(entry.id);});writing.catch(console.error);return writing;
}
async function newGameWindow(){
 try{if(native)await invoke('open_game_window',{level,mode});else{const url=new URL(location.href);url.search='';url.hash=new URLSearchParams({level,mode,new:'1'}).toString();const size=windowSizeForLevel(level);window.open(url.href,'_blank',`popup,width=${size.width},height=${size.height}`);}}
 catch{openModal('windowError');}
}

function restart(next=level){firstMove=null;if(board&&!board.ended)record('abandoned');worker?.terminate();worker=null;generation++;level=next;save('level',level);board=new Board(level);paused=false;generating=false;elapsed=0;start=null;session=null;recorded=false;pressed=-1;dragging=false;focus=0;closeModal();render();fit();}
async function resizeWindow(animate=true){if(!native)return;await transitionWindow({...windowSizeForLevel(level),animate});}
function act(i,mark=false){if(modal||paused||generating||ended()||!board.cells[i])return;focus=i;
 if(mark){board.mark(i);render();return;}
 if(board.cells[i].mark===1)return;
 if(board.phase==='ready'){
   generating=true;pressed=-1;const token=++generation,marks=board.cells.map(c=>c.mark);
   worker=new Worker(new URL('./generator.worker.js',import.meta.url),{type:'module'});
   worker.onmessage=({data})=>{if(token!==generation)return;worker.terminate();worker=null;if(data.error){generating=false;pressed=-1;render();return;}board=Board.restore(data.board);firstMove=i;board.cells.forEach((c,j)=>c.mark=marks[j]);board.flags=marks.filter(x=>x===1).length;generating=false;pressed=-1;session={id:crypto.randomUUID(),startedAt:Date.now()};board.reveal(i);if(!paused)start=performance.now();finish();render();if(modal==='share')paintModal();};
   worker.onerror=()=>{if(token===generation){worker?.terminate();worker=null;generating=false;pressed=-1;render();}};worker.postMessage({level,first:i,mode});render();return;
 }
 board.reveal(i);finish();render();
}
function finish(){if(!ended())return;record(board.phase);paused=false;if(prefs.result)openModal('result');}
function render(){
 if(browserGame){const size=windowSizeForLevel(level);document.documentElement.style.setProperty('--game-width',size.width+'px');document.documentElement.style.setProperty('--game-height',size.height+'px');}snapshotBrowserGame();
 const levelTrigger=$('#level-select');if(levelTrigger&&levelTrigger.dataset.level!==level){levelTrigger.outerHTML=dropdown('level-select','难度',level,Object.entries(names).map(([value,title])=>({value,title})));$('#level-select').dataset.level=level;bindDropdowns($('#level-select').parentElement,(id,value)=>{if(id==='level-select'){restart(value);resizeWindow().catch(()=>{});}});}
 const modeTrigger=$('#mode-select');if(modeTrigger&&modeTrigger.dataset.mode!==mode){modeTrigger.outerHTML=dropdown('mode-select','玩法',mode,Object.entries(modeNames).map(([value,title])=>({value,title})));$('#mode-select').dataset.mode=mode;bindDropdowns($('#mode-select').parentElement,(id,value)=>chooseMode(value));}
 setCounter($('#remaining'),board.mines-board.flags);$('#remaining').setAttribute('aria-label',`剩余雷数 ${board.mines-board.flags}`);
 setTimerCounter($('#timer'),seconds());
 $('#pause').textContent=paused?'继续':'暂停';$('#pause').disabled=(!paused&&board.phase!=='playing')||generating;$('#pause').setAttribute('aria-pressed',String(paused));
 canvas.setAttribute('aria-busy',String(generating));$('#pause-mask').hidden=!(paused&&prefs.mask&&!modal);
 $('#face-eyes').style.opacity=generating?'.4':'1';$('#face-mouth').setAttribute('d',board.phase==='lost'?'M8 24 Q16 14 24 24':paused?'M9 21 L23 21':'M8 19 Q16 29 24 19');draw();
}
function fit(){
 const area=$('.board-area'),frame=$('.board-wrap'),style=getComputedStyle(frame);
 const borderX=parseFloat(style.borderLeftWidth)+parseFloat(style.borderRightWidth),borderY=parseFloat(style.borderTopWidth)+parseFloat(style.borderBottomWidth);
 // Fill the shared panel width and remaining height; glyphs stay centered and proportional.
 if(browserGame){frame.style.width=Math.max(area.clientWidth,board.cols*22+borderX)+'px';frame.style.height=area.clientHeight+'px';}
 canvasWidth=Math.max(1,browserGame?frame.clientWidth:area.clientWidth-borderX);canvasHeight=Math.max(1,browserGame?frame.clientHeight:area.clientHeight-borderY);
 if(browserGame){$('#pause-mask').style.width=area.clientWidth+'px';$('#pause-mask').style.left=area.scrollLeft+'px';}
 tileWidth=canvasWidth/board.cols;tileHeight=canvasHeight/board.rows;tile=Math.min(tileWidth,tileHeight);
 const dpr=devicePixelRatio||1;
 canvas.style.width=`${canvasWidth}px`;canvas.style.height=`${canvasHeight}px`;
 canvas.width=Math.round(canvasWidth*dpr);canvas.height=Math.round(canvasHeight*dpr);
 ctx.setTransform(canvas.width/canvasWidth,0,0,canvas.height/canvasHeight,0,0);draw();
}
function polygon(points,color){ctx.fillStyle=color;ctx.beginPath();points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.fill();}
function drawIcon(image,fraction){const scale=tile*fraction/Math.max(image.width,image.height),w=image.width*scale,h=image.height*scale;ctx.drawImage(image,(tile-w)/2,(tile-h)/2,w,h);}
function drawWrongFlag(){ctx.strokeStyle='#e00';ctx.lineWidth=1.8;ctx.beginPath();ctx.moveTo(3,3);ctx.lineTo(tile-3,tile-3);ctx.moveTo(tile-3,3);ctx.lineTo(3,tile-3);ctx.stroke();}
function draw(){if(!board||!canvas.width)return;const focusedCell=board.cells[focus];canvas.setAttribute('aria-label',`扫雷棋盘，第 ${Math.floor(focus/board.cols)+1} 行，第 ${focus%board.cols+1} 列，${ended()&&focusedCell.mark===1&&!focusedCell.mine?'插旗错误，这里没有雷':focusedCell.mark===1?'已插旗':focusedCell.mark===2?'可疑标记':focusedCell.open?(focusedCell.mine?'地雷':focusedCell.n?`周围 ${focusedCell.n} 颗雷`:'空白'):'未翻开'}`);ctx.clearRect(0,0,canvasWidth,canvasHeight);const colors=['','#2000ff','#008000','#f00','#000080','#800000','#008080','#111','#666'];
 board.cells.forEach((c,i)=>{const x=i%board.cols*tileWidth,y=Math.floor(i/board.cols)*tileHeight,wrong=ended()&&c.mark===1&&!c.mine,mine=ended()&&c.mine;ctx.save();ctx.translate(x,y);ctx.fillStyle=board.exploded===i?'#f00':'#bfbfbf';ctx.fillRect(0,0,tileWidth,tileHeight);const flat=c.open||mine||(!generating&&pressed===i&&c.mark!==1);if(flat){ctx.strokeStyle='#808080';ctx.lineWidth=.6;ctx.strokeRect(.3,.3,tileWidth,tileHeight);}else{const t=tile>=30?2.5:2;polygon([[0,0],[tileWidth,0],[tileWidth-t,t],[t,t],[t,tileHeight-t],[0,tileHeight]],'#fff');polygon([[tileWidth,0],[tileWidth,tileHeight],[0,tileHeight],[t,tileHeight-t],[tileWidth-t,tileHeight-t],[tileWidth-t,t]],'#808080');}
 ctx.save();ctx.translate((tileWidth-tile)/2,(tileHeight-tile)/2);
 if(c.mark===1&&iconImages.flag){drawIcon(iconImages.flag,prefs.small?.55:.72);}
 else if(c.mark===1){ctx.save();const u=tile*(prefs.small?.55:.72)/16;ctx.translate(tile/2-8*u,tile/2-8*u);ctx.scale(u,u);ctx.fillStyle='#000';ctx.fillRect(9,1,2,12);ctx.fillRect(6,12,7,2);ctx.fillRect(3,14,12,2);polygon(prefs.triangle?[[9,1],[2,5],[9,9]]:[[9,1],[2,3],[2,8],[9,6]],'#e00');ctx.restore();}
 else if(mine&&iconImages.mine){drawIcon(iconImages.mine,.72);}
 else if(mine){ctx.strokeStyle=ctx.fillStyle='#080808';ctx.lineWidth=Math.max(1.5,tile*.075);ctx.lineCap='round';ctx.beginPath();for(let j=0;j<8;j++){const a=j*Math.PI/4;ctx.moveTo(tile/2+Math.cos(a)*tile*.2,tile/2+Math.sin(a)*tile*.2);ctx.lineTo(tile/2+Math.cos(a)*tile*.31,tile/2+Math.sin(a)*tile*.31);}ctx.stroke();ctx.beginPath();ctx.arc(tile/2,tile/2,tile*.245,0,Math.PI*2);ctx.fill();ctx.fillStyle='#fff';ctx.beginPath();ctx.ellipse(tile*.42,tile*.4,tile*.055,tile*.045,0,0,Math.PI*2);ctx.fill();}
 else if((c.open&&c.n)||c.mark===2){ctx.fillStyle=c.mark===2?'#000':colors[c.n];ctx.font=`${prefs.rounded?600:700} ${tile*.76}px ${prefs.rounded?'Fredoka, "Arial Rounded MT Bold"':'Arial, sans-serif'}`;ctx.textAlign='left';ctx.textBaseline='alphabetic';const text=c.mark===2?'?':String(c.n),ink=ctx.measureText(text);ctx.fillText(text,tile/2+(ink.actualBoundingBoxLeft-ink.actualBoundingBoxRight)/2,tile/2+(ink.actualBoundingBoxAscent-ink.actualBoundingBoxDescent)/2);}
 if(wrong)drawWrongFlag();
 ctx.restore();
 ctx.restore();});
}
const indexAt=e=>{const r=canvas.getBoundingClientRect(),x=e.clientX-r.left,y=e.clientY-r.top;if(x<0||y<0||x>=r.width||y>=r.height)return -1;return Math.floor(y/r.height*board.rows)*board.cols+Math.floor(x/r.width*board.cols);};
canvas.addEventListener('contextmenu',e=>e.preventDefault());
canvas.addEventListener('pointerdown',e=>{if(modal||paused||generating||ended())return;e.preventDefault();canvas.focus();const i=indexAt(e);if(i<0)return;focus=i;if(browserGame&&e.pointerType==='touch'){touchPress={x:e.clientX,y:e.clientY,mark:browserMarkMode};dragging=true;pressed=i;canvas.setPointerCapture(e.pointerId);draw();return;}if(e.button===2||e.ctrlKey||(!native&&browserMarkMode)){act(i,true);return;}if(e.button===1){if(board.cells[i].open)act(i);return;}if(e.button!==0)return;if(prefs.press)act(i);else{dragging=true;pressed=i;canvas.setPointerCapture(e.pointerId);draw();}});
canvas.addEventListener('pointermove',e=>{if(dragging){pressed=indexAt(e);draw();}});
canvas.addEventListener('pointerup',e=>{if(!dragging)return;dragging=false;pressed=-1;const touch=touchPress;touchPress=null;if(!touch||Math.hypot(e.clientX-touch.x,e.clientY-touch.y)<10)act(indexAt(e),touch?.mark||false);draw();});
canvas.addEventListener('pointercancel',()=>{touchPress=null;dragging=false;pressed=-1;draw();});
canvas.addEventListener('keydown',e=>{if(modal||paused||generating)return;const offsets={ArrowLeft:-1,ArrowRight:1,ArrowUp:-board.cols,ArrowDown:board.cols};if(e.key in offsets){e.preventDefault();e.stopPropagation();const n=focus+offsets[e.key];if(n>=0&&n<board.cells.length&&(Math.abs(offsets[e.key])!==1||Math.floor(n/board.cols)===Math.floor(focus/board.cols)))focus=n;draw();}else if(e.key===' '||e.key==='Enter'){e.preventDefault();e.stopPropagation();act(focus);}else if(e.key.toLowerCase()==='f'){e.preventDefault();e.stopPropagation();act(focus,true);}});
function esc(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function openModal(type){if(type==='share'){shareCode='';shareMessage='';}if(type==='import'){importCode='';importPreview=null;importMessage='';}setMenu(false);pause();modal=type;confirmReset=false;paintModal();render();}
function closeModal(){closeDropdown(false);$('main').inert=false;modal='';confirmReset=false;$('#modal').hidden=true;$('#modal').replaceChildren();canvas.focus({preventScroll:true});renderIfReady();}
function renderIfReady(){if(board)render();}
function setting(key,title,a,b){return `<div class="setting-row"><span>${title}</span>${dropdown('pref-'+key,title,String(prefs[key]),[{value:'true',title:a},{value:'false',title:b}],key==='triangle'&&!!customIcons.flag)}</div>`;}
function defaultBoardIcon(kind){
 const flag=`<path d="M9 1h2v12H9zM6 12h7v2H6zM3 14h12v2H3z" fill="#000"/><path d="${prefs.triangle?'M9 1 2 5 9 9Z':'M9 1 2 3 2 8 9 6Z'}" fill="#e00"/>`;
 const mine='<g stroke="#080808" stroke-width="1.5" stroke-linecap="round"><path d="M8 2v12M2 8h12M4 4l8 8M4 12l8-8"/></g><circle cx="8" cy="8" r="4.8" fill="#080808"/><ellipse cx="6.5" cy="6" rx="1.1" ry=".9" fill="white"/>';
 return `<svg viewBox="0 0 16 16" aria-hidden="true" class="board-icon-preview">${kind==='flag'?flag:mine}</svg>`;
}
function paintModal(){$('main').inert=true;closeDropdown(false);const active=document.activeElement,focusSelector=active?.id?'#'+active.id:active?.dataset.tab?'[data-tab="'+active.dataset.tab+'"]':null;const layer=$('#modal');layer.hidden=false;let body='',title={history:'历史记录',settings:'设置',result:board.phase==='won'?'获胜':'踩雷',windowError:'新建窗口',share:'分享本局',import:'导入对局'}[modal];
 if(modal==='settings'){
  const tabs=`<nav class="settings-tabs" aria-label="设置分类">${[['game','游戏'],['icons','图标']].map(([key,name])=>`<button data-tab="${key}" aria-pressed="${settingsTab===key}">${name}</button>`).join('')}</nav>`;
  const content=settingsTab==='game'?`${setting('press','翻格时机','按下时','松开时')}${setting('rounded','棋盘数字','圆润','经典')}${setting('triangle','旗子形状','三角旗','方旗')}${setting('small','旗子大小','小巧','标准')}${setting('mask','暂停遮罩','开启','关闭')}${setting('result','完成后显示结果','开启','关闭')}`:`${['app','flag','mine'].map(kind=>`<div class="icon-row"><div class="icon-preview" data-kind="${kind}">${customIcons[kind]?`<img src="${esc(customIcons[kind])}" alt="">`:kind==='app'?`<img src="${defaultAppIcon}" alt="">`:defaultBoardIcon(kind)}</div><span>${{app:native?'应用':'网页',flag:'旗子',mine:'地雷'}[kind]}</span><span class="spacer"></span><button data-icon-choose="${kind}" ${iconBusy?'disabled':''} aria-label="更换${{app:native?'应用':'网页',flag:'旗子',mine:'地雷'}[kind]}图标">更换</button><button data-icon-reset="${kind}" ${iconBusy||!customIcons[kind]?'disabled':''} aria-label="恢复${{app:native?'应用':'网页',flag:'旗子',mine:'地雷'}[kind]}图标">恢复</button></div>`).join('')}<small class="muted">${native?'应用图标用于窗口与任务栏':'网页图标只保存在当前浏览器'}</small><p class="icon-message" role="status">${esc(iconMessage)}</p>`;
  body=`${tabs}<div class="settings-list">${content}</div>`;
 }
 if(modal==='result'){
  const stats=gameStatistics(history,level,mode);
  body=`<div class="result-time" aria-label="本局用时 ${formatDuration(seconds())}">${formatDuration(seconds())}</div><p class="muted">${names[level]} · ${modeNames[mode]}${best[bestKey()]!=null?` · 最佳 ${formatDuration(best[bestKey()])}`:''}</p><div class="metrics" aria-label="${names[level]}统计"><div><span>总局数</span><b>${stats.total}</b></div><div><span>获胜</span><b>${stats.wins}</b></div><div><span>胜率</span><b>${stats.winRate}</b></div></div><footer><button id="view-board">返回</button><button id="play-again">再来一局</button></footer>`;
 }
 if(modal==='history'){
  const rows=filterHistory(history,{level:filter,mode:modeFilter,result:resultFilter,range:dateFilter,order:historyOrder}),stats=gameStatistics(rows),bestTime=rows.filter(r=>r.result==='won').reduce((best,r)=>Math.min(best,r.seconds),Infinity);
  const choices=items=>items.map(([value,title])=>({value,title}));
  body=`<div class="history-toolbar"><span>难度</span>${dropdown('history-filter','难度筛选',filter,[{value:'all',title:'全部难度'},...Object.entries(names).map(([value,title])=>({value,title}))])}${dropdown('history-mode','玩法筛选',modeFilter,[{value:'all',title:'全部玩法'},...Object.entries(modeNames).map(([value,title])=>({value,title}))])}${dropdown('history-result','结果筛选',resultFilter,choices(historyResults))}${dropdown('history-range','日期筛选',dateFilter,choices(historyRanges))}${dropdown('history-order','排序',historyOrder,choices(historyOrders))}<button id="reset-filters" ${filter==='all'&&modeFilter==='all'&&resultFilter==='all'&&dateFilter==='all'&&historyOrder==='newest'?'disabled':''}>重置筛选</button></div><div class="metrics"><div><span>总局数</span><b>${stats.total}</b></div><div><span>获胜</span><b>${stats.wins}</b></div><div><span>胜率</span><b>${stats.winRate}</b></div><div><span>最佳用时</span><b>${Number.isFinite(bestTime)?formatDuration(bestTime):'—'}</b></div></div><div class="records" tabindex="0" role="region" aria-label="对局记录">${rows.length?rows.map(r=>{
   const result=['won','lost','abandoned'].includes(r.result)?r.result:'abandoned';
   return `<article><div class="record-meta"><span class="record-level">${esc(names[r.level]||r.level)} · ${modeNames[r.mode||'logical']||modeNames.logical}</span><time>${esc(new Date(r.endedAt).toLocaleString('zh-CN',{hour12:false}))}</time></div><span class="record-result ${result}">${{won:'获胜',lost:'踩雷',abandoned:'未完成'}[result]}</span><strong>${formatDuration(r.seconds)}</strong></article>`;
  }).join(''):`<div class="empty"><strong>${history.length?'没有符合条件的记录':'暂无记录'}</strong><span>${history.length?'试试调整或重置筛选':'完成一局后，在这里查看'}</span></div>`}</div><footer class="history-footer"><span>显示 ${rows.length} / ${history.length} 局</span><button id="clear-history" ${history.length?'':'disabled'}>清空记录</button></footer>${confirmReset?'<div class="confirm-layer"><div class="confirm" role="alertdialog" aria-modal="true" aria-labelledby="reset-title"><div class="dialog-heading"><h2 id="reset-title">清空记录？</h2><button id="cancel-reset-x" aria-label="关闭确认">×</button></div><p>将清空所有难度的记录和最佳用时，无法恢复</p><footer><button id="cancel-reset">取消</button><button id="reset-records">确认清空</button></footer></div></div>':''}`;
 }
 if(modal==='share'){
  const available=firstMove!==null&&board.phase!=='ready'&&!generating;
  body=available?`<p class="game-id">${gameID(board,mode,firstMove)}</p><p class="muted">分享码可在 Mac、Windows 和网页导入</p><button id="copy-challenge">复制本局挑战</button><p class="muted">相同雷区和首步位置，用时从零开始</p><button id="copy-progress" ${board.phase==='playing'?'':'disabled'}>复制当前进度</button><p class="muted">保留翻格、旗子、问号和用时</p><textarea id="share-code" aria-label="分享码" readonly ${shareCode?'':'hidden'}>${esc(shareCode)}</textarea><p id="share-message" class="muted" role="status">${esc(shareMessage)}</p>`:'<p class="muted">翻开第一格后即可分享本局</p>';
 }
 if(modal==='import'){
  body=`<label class="muted" for="import-code">粘贴挑战码或进度码</label><textarea id="import-code" maxlength="2048" spellcheck="false" aria-label="分享码">${esc(importCode)}</textarea><button id="inspect-code">读取分享码</button><div id="import-preview">${importPreview?`<p class="game-id">${importPreview.id}</p><p class="muted">${names[importPreview.board.level]} · ${modeNames[importPreview.mode]}</p><p class="muted">${importPreview.progress?`已翻开 ${importPreview.board.opened} 格 · ${formatDuration(importPreview.seconds)}`:'这份分享码只包含雷区'}</p><footer><button id="import-challenge">从头挑战</button>${importPreview.progress?'<button id="import-progress">继续进度</button>':''}</footer>`:''}</div><p id="import-message" class="muted" role="status">${esc(importMessage)}</p>`;
 }
 if(modal==='windowError')body='<p role="status">暂时无法打开新窗口</p>';
 layer.innerHTML=`<section class="modal-card ${modal}" role="dialog" aria-modal="true" aria-labelledby="dialog-title"><div class="dialog-heading"><h2 id="dialog-title">${title}</h2><button id="close-modal" aria-label="关闭弹窗" ${iconBusy?'disabled':''}>×</button></div>${body}</section>`;
 if(confirmReset)layer.querySelector('.history').querySelectorAll(':scope > :not(.confirm-layer)').forEach(element=>element.inert=true);
 $('#close-modal').onclick=()=>{if(confirmReset){confirmReset=false;paintModal();}else closeModal();};
 bindDropdowns(layer,(id,value)=>{if(id==='history-filter'){filter=value;paintModal();}else if(id==='history-mode'){modeFilter=value;paintModal();}else if(id==='history-result'){resultFilter=value;paintModal();}else if(id==='history-range'){dateFilter=value;paintModal();}else if(id==='history-order'){historyOrder=value;paintModal();}else{const key=id.slice(5);prefs[key]=value==='true';persist('settings',{[key]:prefs[key]});render();}});
 if(modal==='settings'){
  layer.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{settingsTab=b.dataset.tab;iconMessage='';paintModal();});
  layer.querySelectorAll('[data-icon-choose]').forEach(b=>b.onclick=()=>changeIcon(b.dataset.iconChoose,false));
  layer.querySelectorAll('[data-icon-reset]').forEach(b=>b.onclick=()=>changeIcon(b.dataset.iconReset,true));
 }
 if(modal==='result'){$('#view-board').onclick=closeModal;$('#play-again').onclick=()=>restart();}
 if(modal==='history'){$('#reset-filters').onclick=()=>{filter=modeFilter=resultFilter=dateFilter='all';historyOrder='newest';paintModal();};$('#clear-history').onclick=()=>{confirmReset=true;paintModal();};if(confirmReset){$('#cancel-reset-x').onclick=()=>{confirmReset=false;paintModal();};$('#cancel-reset').onclick=()=>{confirmReset=false;paintModal();};$('#reset-records').onclick=()=>{persist('clear',null).then(()=>{confirmReset=false;paintModal();});};}}
 if(modal==='share'){
  if($('#copy-challenge'))$('#copy-challenge').onclick=()=>copyGame(false);
  if($('#copy-progress'))$('#copy-progress').onclick=()=>copyGame(true);
 }
 if(modal==='import'){
  $('#import-code').oninput=e=>{importCode=e.target.value;importPreview=null;importMessage='';$('#import-preview').replaceChildren();$('#import-message').textContent='';};
  $('#inspect-code').onclick=()=>{try{importPreview=decodeGame(importCode);importMessage='';}catch(error){importPreview=null;importMessage=error.message;}paintModal();};
  if($('#import-challenge'))$('#import-challenge').onclick=()=>applyShared(false);
  if($('#import-progress'))$('#import-progress').onclick=()=>applyShared(true);
 }
 if(confirmReset)$('#cancel-reset').focus({preventScroll:true});else (focusSelector?layer.querySelector(focusSelector):null)?.focus({preventScroll:true});
 if(!layer.contains(document.activeElement))layer.querySelector('button:not(:disabled)')?.focus({preventScroll:true});
}
async function copyGame(progress){
 try{
  shareCode=encodeGame(board,mode,firstMove,seconds(),progress);
  const area=$('#share-code');area.hidden=false;area.value=shareCode;
  try{if(native)await writeClipboard(shareCode);else await navigator.clipboard.writeText(shareCode);shareMessage=progress?'已复制进度码':'已复制挑战码';}
  catch{shareMessage='未能写入剪贴板，可选中分享码复制';if(modal==='share'){area.focus();area.select();}}
 }catch(error){shareMessage=error.message;}
 if(modal==='share')$('#share-message').textContent=shareMessage;
}
function applyShared(continueProgress){if(importPreview)loadShared(importPreview,continueProgress);}
function loadShared(shared,continueProgress,startPaused=false,restoredSession=null){
 const restored=restoreGame(shared,continueProgress);
 restart(restored.board.level);mode=restored.mode;save('mode',mode);board=restored.board;firstMove=restored.first;
 elapsed=restored.seconds*1000;session=restoredSession??{id:crypto.randomUUID(),startedAt:Date.now()};recorded=false;paused=startPaused;start=board.phase==='playing'&&!paused?performance.now():null;
 finish();render();fit();resizeWindow().catch(console.error);
}
function snapshotBrowserGame(){
 if(!browserGame||!board)return;
 try{
  if(board.phase==='playing'&&firstMove!==null&&!generating)sessionStorage.setItem(localKey('active-game'),JSON.stringify({code:encodeGame(board,mode,firstMove,seconds(),true),session}));
  else if(!generating)sessionStorage.removeItem(localKey('active-game'));
 }catch{reportStorageError();}
}
function restoreBrowserGame(){
 if(!browserGame)return;
 try{
  if(windowOptions.get('new')==='1'){sessionStorage.removeItem(localKey('active-game'));windowOptions.delete('new');const url=new URL(location.href);url.hash=windowOptions.toString();window.history.replaceState(null,'',url);return;}
  const saved=sessionStorage.getItem(localKey('active-game'));if(saved){const checkpoint=saved.startsWith('MS1.')?{code:saved}:JSON.parse(saved);const previous=checkpoint.session,valid=previous&&typeof previous.id==='string'&&previous.id.length<=64&&Number.isSafeInteger(previous.startedAt)&&previous.startedAt>0;loadShared(decodeGame(checkpoint.code),true,true,valid?previous:null);}
 }catch{sessionStorage.removeItem(localKey('active-game'));}
}
async function changeIcon(kind,reset){if(iconBusy)return;iconBusy=true;iconMessage='';paintModal();try{await (reset?resetIcon:chooseIcon)(kind,()=>{draw();if(modal==='settings'&&settingsTab==='icons')paintModal();});}catch(error){iconMessage=typeof error==='string'?error:error.message||'暂时无法读取这张图片';}finally{iconBusy=false;if(modal==='settings')paintModal();}}
$('#restart').onclick=()=>restart();$('#pause').onclick=()=>paused?resume():pause();$('#resume').onclick=resume;$('#menu-toggle').onclick=()=>setMenu($('#top-menu').hidden);
function setMenu(open){if(open)closeDropdown(false);$('#top-menu').hidden=!open;$('#menu-toggle').setAttribute('aria-expanded',String(open));}
$('#top-menu').querySelectorAll('[data-menu]').forEach(b=>b.onclick=()=>{setMenu(false);if(b.dataset.menu==='new')restart();else if(b.dataset.menu==='window')newGameWindow();else openModal(b.dataset.menu);});
document.addEventListener('pointerdown',e=>{if(!e.target.closest('.menu-wrap'))setMenu(false);});
$('#menu-toggle').addEventListener('keydown',e=>{if(e.key==='ArrowDown'){e.preventDefault();setMenu(true);$('#top-menu button').focus();}});
$('#top-menu').addEventListener('keydown',e=>{const items=[...$('#top-menu').querySelectorAll('button')],i=items.indexOf(document.activeElement);if(['ArrowDown','ArrowUp','Home','End'].includes(e.key)){e.preventDefault();items[e.key==='Home'?0:e.key==='End'?items.length-1:(i+(e.key==='ArrowDown'?1:-1)+items.length)%items.length].focus();}});
window.addEventListener('blur',pause);document.addEventListener('visibilitychange',()=>{if(document.hidden)pause();});
window.addEventListener('pagehide',()=>{if(browserGame)snapshotBrowserGame();else record('abandoned');});
document.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.shiftKey&&e.key.toLowerCase()==='n'){e.preventDefault();newGameWindow();return;}if(e.key==='Escape'&&!$('#top-menu').hidden){e.preventDefault();setMenu(false);$('#menu-toggle').focus();return;}if(e.key==='Escape'&&modal&&!iconBusy){e.preventDefault();if(confirmReset){confirmReset=false;paintModal();}else closeModal();return;}if(modal){if(e.key==='Tab'){const items=[...(confirmReset?$('.confirm'):$('#modal')).querySelectorAll('button:not(:disabled),select:not(:disabled),textarea:not(:disabled),[tabindex="0"]')].filter(el=>el.getClientRects().length);const first=items[0],last=items.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}if(e.key==='Enter'&&modal==='result'&&e.target.id!=='view-board'&&e.target.id!=='close-modal'){e.preventDefault();restart();}return;}if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='y'){e.preventDefault();openModal('history');}if((e.ctrlKey||e.metaKey)&&['1','2','3'].includes(e.key)){e.preventDefault();restart(['easy','medium','hard'][Number(e.key)-1]);resizeWindow().catch(()=>{});}if((e.ctrlKey||e.metaKey)&&e.key===','){e.preventDefault();openModal('settings');}if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='p'){e.preventDefault();paused?resume():pause();}if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='n'){e.preventDefault();e.shiftKey?newGameWindow():restart();}});
let checkpoint;try{checkpoint=browserGame?sessionStorage.getItem(localKey('active-game')):null;}catch{}
restart();if(checkpoint&&browserGame)try{sessionStorage.setItem(localKey('active-game'),checkpoint);}catch{}restoreBrowserGame();loadIcons(()=>{draw();if(modal==='settings'&&settingsTab==='icons')paintModal();});new ResizeObserver(fit).observe($('.board-area'));document.fonts.load('600 24px Fredoka').then(draw);document.fonts.ready.then(draw);setInterval(()=>{const s=seconds();if(lastSecond!==s){lastSecond=s;setTimerCounter($('#timer'),s);snapshotBrowserGame();}},200);
if(native){resizeWindow(false).catch(console.error);getCurrentWindow().onCloseRequested(async()=>{try{await record('abandoned');await pendingWrites;}catch(error){console.error(error);}finally{worker?.terminate();}}).catch(console.error);}

window.addEventListener('focus',()=>{libraryReady.then(request=>request('load')).catch(console.error);loadIcons(()=>{draw();if(modal==='settings'&&settingsTab==='icons')paintModal();});});

$('.board-area').addEventListener('scroll',()=>{if(browserGame)$('#pause-mask').style.left=$('.board-area').scrollLeft+'px';});
