export function gameStatistics(history,level='all',mode='all'){
 const rows=history.filter(record=>(level==='all'||record.level===level)&&(mode==='all'||(record.mode||'logical')===mode));
 const wins=rows.filter(record=>record.result==='won').length;
 const finished=rows.filter(record=>record.result==='won'||record.result==='lost').length;
 return {total:rows.length,wins,finished,winRate:finished?Math.round(wins/finished*100)+'%':'—'};
}
