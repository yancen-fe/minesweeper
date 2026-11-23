import {generateForMode} from './engine.js';
self.onmessage=({data})=>{try{const {board,tries}=generateForMode(data.level,data.first,data.mode);self.postMessage({board,tries});}catch{self.postMessage({error:true});}};
