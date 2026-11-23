export const nativeStorage=!!globalThis.window?.__TAURI_INTERNALS__;
export const localKey=key=>nativeStorage?key:`minesweeper:web:v1:${key}`;
export function readLocal(key,fallback){try{return JSON.parse(localStorage.getItem(localKey(key)))??fallback;}catch{return fallback;}}
export function writeLocal(key,value){localStorage.setItem(localKey(key),JSON.stringify(value));}
export function reportStorageError(){globalThis.window?.dispatchEvent(new Event('minesweeper-storage-error'));}
