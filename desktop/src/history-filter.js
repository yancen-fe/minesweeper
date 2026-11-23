export const historyResults=[['all','全部结果'],['won','获胜'],['lost','踩雷'],['abandoned','未完成']];
export const historyRanges=[['all','全部时间'],['today','今天'],['7','近 7 天'],['30','近 30 天']];
export const historyOrders=[['newest','最新在前'],['oldest','最早在前'],['fastest','用时最短'],['slowest','用时最长']];
export function filterHistory(history,{level='all',mode='all',result='all',range='all',order='newest'}={},now=new Date()){
 let lower=-Infinity,upper=Infinity;
 if(range!=='all'){
  const start=new Date(now);start.setHours(0,0,0,0);const end=new Date(start);end.setDate(end.getDate()+1);upper=end.getTime();
  start.setDate(start.getDate()-(range==='7'?6:range==='30'?29:0));lower=start.getTime();
 }
 return history.filter(r=>(level==='all'||r.level===level)&&(mode==='all'||(r.mode||'logical')===mode)&&(result==='all'||r.result===result)&&r.endedAt>=lower&&r.endedAt<upper)
 .sort((a,b)=>{const time=b.endedAt-a.endedAt,tie=String(a.id).localeCompare(String(b.id));return (order==='oldest'?-time:order==='fastest'?a.seconds-b.seconds||time:order==='slowest'?b.seconds-a.seconds||time:time)||tie;});
}
