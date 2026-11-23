import {fileURLToPath} from 'node:url';
const configFile=fileURLToPath(new URL('../vite.config.mjs',import.meta.url));
let vite;try{vite=await import('../../desktop/node_modules/vite/dist/node/index.js');}catch{console.error('请先运行 npm --prefix desktop ci');process.exit(1);}
const command=process.argv[2]||'dev';
const port=Number(process.env.PORT)||5173;
if(command==='build')await vite.build({configFile});
else {const server=command==='preview'?await vite.preview({configFile,preview:{port}}):await vite.createServer({configFile,server:{port}});if(command!=='preview')await server.listen();server.printUrls();}
