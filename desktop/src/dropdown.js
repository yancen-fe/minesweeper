const definitions=new Map();
const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let opened=null;
export function dropdown(id,label,value,choices,disabled=false){
  definitions.set(id,{label,value,choices});
  const text=choices.find(c=>c.value===value)?.title||'';
  return `<button id="${escape(id)}" class="classic-combo" role="combobox" aria-label="${escape(label)}" aria-haspopup="listbox" aria-expanded="false" aria-controls="classic-options" data-dropdown="${escape(id)}" ${disabled?'disabled':''}><span class="combo-value">${escape(text)}</span><span class="combo-arrow" aria-hidden="true"></span></button>`;
}
export function closeDropdown(restore=true){
  if(!opened)return;
  const {trigger,popup,dialog}=opened;opened=null;dialog?.removeAttribute('aria-owns');popup.remove();trigger.setAttribute('aria-expanded','false');trigger.removeAttribute('aria-activedescendant');
  if(restore&&trigger.isConnected)trigger.focus();
}
function position(){
  if(!opened)return;
  const {trigger,popup}=opened,r=trigger.getBoundingClientRect(),w=Math.min(Math.max(124,r.width),innerWidth-16),h=popup.offsetHeight;
  popup.style.width=w+'px';popup.style.left=Math.max(8,Math.min(r.left,innerWidth-w-8))+'px';
  popup.style.top=Math.max(8,Math.min(r.bottom+3+h<=innerHeight-8?r.bottom+3:r.top-h-3,innerHeight-h-8))+'px';
}
function highlight(index){
  if(!opened)return;
  const {definition,popup,trigger}=opened,n=definition.choices.length;
  opened.index=(index+n)%n;
  popup.querySelectorAll('[role=option]').forEach((el,i)=>el.classList.toggle('highlighted',i===opened.index));
  const id='classic-option-'+opened.index;popup.setAttribute('aria-activedescendant',id);trigger.setAttribute('aria-activedescendant',id);
}
function commit(index){
  if(!opened)return;
  const {trigger,definition,onChange}=opened,choice=definition.choices[index];
  if(!choice)return;
  definition.value=choice.value;trigger.querySelector('.combo-value').textContent=choice.title;
  const id=trigger.dataset.dropdown;closeDropdown();onChange(id,choice.value);
}
function open(trigger,onChange,direction=0){
  if(opened?.trigger===trigger){closeDropdown();return;}
  closeDropdown(false);
  const definition=definitions.get(trigger.dataset.dropdown);
  if(!definition||trigger.disabled)return;
  const popup=document.createElement('div');popup.id='classic-options';popup.className='classic-options';popup.tabIndex=-1;popup.setAttribute('role','listbox');popup.setAttribute('aria-label',definition.label);
  popup.innerHTML=definition.choices.map((c,i)=>`<div role="option" id="classic-option-${i}" aria-selected="${c.value===definition.value}" data-option="${i}"><span class="combo-check" aria-hidden="true">${c.value===definition.value?'✓':''}</span><span>${escape(c.title)}</span></div>`).join('');
  const dialog=trigger.closest('[role=dialog]');dialog?.setAttribute('aria-owns','classic-options');
  opened={trigger,popup,dialog,definition,onChange,index:Math.max(0,definition.choices.findIndex(c=>c.value===definition.value))};
  document.body.append(popup);trigger.setAttribute('aria-expanded','true');position();highlight(direction?opened.index+direction:opened.index);popup.focus();
  popup.addEventListener('pointermove',e=>{const row=e.target.closest('[data-option]');if(row)highlight(Number(row.dataset.option));});
  popup.addEventListener('pointerdown',e=>e.preventDefault());
  popup.addEventListener('click',e=>{const row=e.target.closest('[data-option]');if(row)commit(Number(row.dataset.option));});
  popup.addEventListener('keydown',e=>{
    if(['ArrowDown','ArrowUp','Home','End','Enter',' ','Escape','Tab'].includes(e.key)){if(e.key!=='Tab'){e.stopPropagation();e.preventDefault();}}
    if(e.key==='ArrowDown')highlight(opened.index+1);else if(e.key==='ArrowUp')highlight(opened.index-1);
    else if(e.key==='Home')highlight(0);else if(e.key==='End')highlight(definition.choices.length-1);
    else if(e.key==='Enter'||e.key===' ')commit(opened.index);else if(e.key==='Escape'||e.key==='Tab')closeDropdown();
  });
}
export function bindDropdowns(root,onChange){
  root.querySelectorAll('[data-dropdown]').forEach(trigger=>{
    trigger.addEventListener('click',()=>open(trigger,onChange));
    trigger.addEventListener('keydown',e=>{if(['ArrowDown','ArrowUp','Enter',' '].includes(e.key)){e.preventDefault();e.stopPropagation();open(trigger,onChange,e.key==='ArrowUp'?-1:0);}});
  });
}
document.addEventListener('pointerdown',e=>{if(opened&&!opened.popup.contains(e.target)&&!opened.trigger.contains(e.target))closeDropdown(false);},true);
window.addEventListener('resize',position);window.addEventListener('blur',()=>closeDropdown(false));
document.addEventListener('scroll',()=>closeDropdown(false),true);
