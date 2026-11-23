import {formatDuration,elapsedSeconds} from './duration.js';
// Seven-segment counters use vector strokes so their appearance is identical on Windows.
const segments={
 a:'M3 1H11L13 3 11 5H3L1 3Z',
 b:'M12 4 14 2V13L12 15 10 13V6Z',
 c:'M12 17 14 15V26L12 28 10 26V19Z',
 d:'M3 25H11L13 27 11 29H3L1 27Z',
 e:'M2 17 4 19V26L2 28 0 26V15Z',
 f:'M2 4 4 6V13L2 15 0 13V2Z',
 g:'M3 13H11L13 15 11 17H3L1 15Z'
};
const digits=['abcdef','bc','abdeg','abcdg','bcfg','acdfg','acdefg','abc','abcdefg','abcdfg'];
export function counterMarkup(value){
 const number=Number(value);
 const integer=Number.isFinite(number)?Math.trunc(number):0;
 const text=(integer<0?'-':'')+String(Math.abs(integer)).padStart(integer<0?2:3,'0');
 return `<svg viewBox="0 0 ${text.length*18+4} 32" aria-hidden="true" focusable="false">${[...text].map((digit,i)=>{
  const active=digit==='-'?'g':digits[Number(digit)];
  return `<g transform="translate(${i*18+4} 1)">${Object.entries(segments).map(([key,path])=>`<path d="${path}" fill="${active.includes(key)?'#ff1008':'#190000'}"/>`).join('')}</g>`;
 }).join('')}</svg>`;
}
export function setCounter(element,value){
 if(element.dataset.value===String(value))return;
 element.dataset.value=String(value);
 element.innerHTML=counterMarkup(value);
}

export function setTimerCounter(element,seconds){
 const elapsed=elapsedSeconds(seconds);
 const display=Math.min(99999,elapsed);
 setCounter(element,display);
 element.dataset.digits=String(Math.max(3,String(display).length));
 element.setAttribute('aria-label',`用时 ${formatDuration(elapsed)}`);
}
