import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {mockIPC,mockWindows,clearMocks} from '@tauri-apps/api/mocks';
import {getCurrentWindow} from '@tauri-apps/api/window';
import {emit,TauriEvent} from '@tauri-apps/api/event';

test('the close-request lifecycle can destroy the main window after saving the game',async()=>{
  const capability=JSON.parse(await readFile(new URL('../src-tauri/capabilities/default.json',import.meta.url),'utf8'));
  const originalWindow=globalThis.window;
  globalThis.window={crypto:globalThis.crypto};
  const calls=[];
  try{
    mockWindows('main');
    mockIPC((command,args)=>{
      assert.equal(command,'plugin:window|destroy');
      assert.ok(capability.windows.includes(args.label));
      assert.ok(capability.permissions.includes('core:window:allow-destroy'),'closing a window with onCloseRequested requires destroy permission');
      calls.push('destroy');
    },{shouldMockEvents:true});
    let saved=false;
    const unlisten=await getCurrentWindow().onCloseRequested(()=>{saved=true;calls.push('save');});
    await emit(TauriEvent.WINDOW_CLOSE_REQUESTED);
    await new Promise(resolve=>setImmediate(resolve));
    assert.equal(saved,true);
    assert.deepEqual(calls,['save','destroy']);
    await unlisten();
  }finally{
    clearMocks();
    if(originalWindow===undefined)delete globalThis.window;
    else globalThis.window=originalWindow;
  }
});

test('a secondary game window waits for its save and closing it does not destroy another window',async()=>{
  const capability=JSON.parse(await readFile(new URL('../src-tauri/capabilities/default.json',import.meta.url),'utf8'));
  const originalWindow=globalThis.window;globalThis.window={crypto:globalThis.crypto};const calls=[];
  try{
    mockWindows('game-1','game-2');mockIPC((command,args)=>{assert.equal(command,'plugin:window|destroy');assert.equal(args.label,'game-1');assert.ok(capability.windows.includes('game-*'));calls.push('destroy-one');},{shouldMockEvents:true});
    const unlisten=await getCurrentWindow().onCloseRequested(async()=>{await new Promise(resolve=>setImmediate(resolve));calls.push('saved-one');});
    await emit(TauriEvent.WINDOW_CLOSE_REQUESTED);await new Promise(resolve=>setTimeout(resolve,20));assert.deepEqual(calls,['saved-one','destroy-one']);await unlisten();
  }finally{clearMocks();if(originalWindow===undefined)delete globalThis.window;else globalThis.window=originalWindow;}
});
