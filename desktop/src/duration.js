export function elapsedSeconds(value){const n=Number(value);return Number.isFinite(n)?Math.max(0,Math.floor(n)):0;}
export function formatDuration(value){const s=elapsedSeconds(value);return s<60?`${s} 秒`:`${Math.floor(s/60)} 分 ${String(s%60).padStart(2,'0')} 秒`;}
