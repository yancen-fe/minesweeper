import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';

const {GITHUB_REF_TYPE: refType, GITHUB_REF_NAME: tag} = process.env;
const match = tag?.match(/^minesweeper-v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))$/);
if (refType !== 'tag' || !match || match[0] !== tag) {
    throw new Error('需要正式发布 tag，格式为 minesweeper-vX.Y.Z');
}
const version = match[1];
for (const file of ['release/channel.json', 'desktop/package.json', 'desktop/src-tauri/tauri.conf.json']) {
    const config = JSON.parse(readFileSync(file, 'utf8'));
    if (config.version !== version) {
        throw new Error(`${file} 中的版本必须与正式发布 tag 一致`);
    }
}

mkdirSync('release/artifacts', {recursive: true});
writeFileSync('release/artifacts/update-tag.json', JSON.stringify({tag}, null, 2) + '\n');
