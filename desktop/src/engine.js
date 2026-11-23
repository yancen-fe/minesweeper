export const LEVELS = { easy:[9,9,10], medium:[16,16,40], hard:[16,30,99] };
export class Board {
  constructor(level='easy', random=Math.random) {
    if (!LEVELS[level]) throw Error('Invalid difficulty');
    this.level=level; [this.rows,this.cols,this.mines]=LEVELS[level]; Object.defineProperty(this,'random',{value:random});
    this.cells=Array.from({length:this.rows*this.cols},()=>({mine:false,n:0,open:false,mark:0}));
    this.neighbors=this.cells.map((_,i)=>{
      const out=[], r=Math.floor(i/this.cols), c=i%this.cols;
      for(let dr=-1;dr<=1;dr++) for(let dc=-1;dc<=1;dc++) if((dr||dc)&&r+dr>=0&&r+dr<this.rows&&c+dc>=0&&c+dc<this.cols) out.push((r+dr)*this.cols+c+dc);
      return out;
    });
    this.phase='ready';this.flags=0;this.opened=0;this.exploded=-1;
  }
  plant(first) {
    const safe=new Set([first,...this.neighbors[first]]), pool=this.cells.map((_,i)=>i).filter(i=>!safe.has(i));
    for(let i=pool.length-1;i>0;i--) {const j=Math.floor(this.random()*(i+1));[pool[i],pool[j]]=[pool[j],pool[i]];}
    pool.slice(0,this.mines).forEach(i=>this.cells[i].mine=true);
    this.cells.forEach((c,i)=>c.n=this.neighbors[i].filter(n=>this.cells[n].mine).length);this.phase='playing';
  }
  mark(i) {
    const c=this.cells[i];if(!c||c.open||this.ended)return;
    if(c.mark===0){c.mark=this.flags<this.mines?1:2;if(c.mark===1)this.flags++;}
    else if(c.mark===1){c.mark=2;this.flags--;}else c.mark=0;
  }
  get ended(){return this.phase==='won'||this.phase==='lost';}
  reveal(i) {
    const c=this.cells[i];if(!c||c.mark===1||this.ended||this.phase==='ready')return;
    if(c.open){if(c.n&&this.neighbors[i].filter(n=>this.cells[n].mark===1).length===c.n)this.open(this.neighbors[i]);}
    else this.open([i]);
  }
  open(queue) {
    queue=[...queue];while(queue.length&&!this.ended){
      const i=queue.pop(),c=this.cells[i];if(c.open||c.mark===1)continue;
      c.open=true;c.mark=0;if(c.mine){this.phase='lost';this.exploded=i;return;}
      this.opened++;if(!c.n)queue.push(...this.neighbors[i]);
    }
    if(this.opened===this.cells.length-this.mines){this.phase='won';this.flags=this.mines;this.cells.forEach(c=>{if(c.mine)c.mark=1;});}
  }
  static restore(data){const b=new Board(data.level);Object.assign(b,data);return b;}
}
const diff=(a,b)=>new Set([...a].filter(x=>!b.has(x)));
export function deductions(visible,neighbors,total,known) {
  const unknown=new Set(visible.flatMap((c,i)=>!c.open&&!known.has(i)?[i]:[]));
  const safe=new Set(), mines=new Set(), equations=[], keys=new Set();
  function add(cells,n){const key=[...cells].sort((a,b)=>a-b).join(',')+':'+n;if(!keys.has(key)){keys.add(key);equations.push({cells,n});}}
  visible.forEach((c,i)=>{if(c.open&&c.n){const cells=new Set(neighbors[i].filter(n=>!visible[n].open&&!known.has(n)));const n=c.n-neighbors[i].filter(n=>known.has(n)).length;if(cells.size&&n>=0&&n<=cells.size)add(cells,n);}});
  const remaining=total-known.size;
  if(remaining===0)return {safe:unknown,mines};if(remaining===unknown.size)return{safe,mines:unknown};
  for(const e of equations){if(e.n===remaining)diff(unknown,e.cells).forEach(x=>safe.add(x));if(unknown.size-e.cells.size===remaining-e.n)diff(unknown,e.cells).forEach(x=>mines.add(x));}
  for(let i=0;i<equations.length;i++){
    const a=equations[i];if(a.n===0)a.cells.forEach(x=>safe.add(x));else if(a.n===a.cells.size)a.cells.forEach(x=>mines.add(x));
    if(safe.size||mines.size)return{safe,mines};
    for(let j=0;j<i;j++){
      const b=equations[j];let small=a,large=b;if(small.cells.size>large.cells.size)[small,large]=[large,small];
      if(small.cells.size===large.cells.size||![...small.cells].every(x=>large.cells.has(x)))continue;
      const cells=diff(large.cells,small.cells),n=large.n-small.n;if(n<0||n>cells.size)continue;
      if(n===0)cells.forEach(x=>safe.add(x));else if(n===cells.size)cells.forEach(x=>mines.add(x));
      if(safe.size||mines.size)return{safe,mines};if(equations.length<1200)add(cells,n);
    }
  }
  return{safe,mines};
}
export function isSolvable(board,first) {
  const visible=board.cells.map(()=>({open:false,n:0})),known=new Set();let safe=new Set([first]),opened=0;
  while(safe.size){
    const queue=[...safe];safe.clear();while(queue.length){const i=queue.pop();if(visible[i].open)continue;if(board.cells[i].mine)return false;
      visible[i]={open:true,n:board.cells[i].n};opened++;if(!visible[i].n)queue.push(...board.neighbors[i].filter(n=>!visible[n].open));}
    if(opened===board.cells.length-board.mines)return true;
    while(true){const moves=deductions(visible,board.neighbors,board.mines,known),newMines=diff(moves.mines,known);newMines.forEach(i=>known.add(i));safe=moves.safe;if(safe.size||!newMines.size)break;}
  }
  return false;
}
export function generate(level,first,random=Math.random) {let tries=0;while(true){const b=new Board(level,random);b.plant(first);tries++;if(isSolvable(b,first))return{board:b,tries};}}

export function generateForMode(level,first,mode='logical',random=Math.random){
 if(mode==='classic'){const board=new Board(level,random);board.plant(first);return {board,tries:1};}
 return generate(level,first,random);
}
