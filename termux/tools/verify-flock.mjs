// 验证补丁后的 flock.js：直接 import dsh 实际使用的那个模块，跑「加锁 / 竞争 / 释放后重取」
import { pathToFileURL } from 'node:url';
import { openSync, closeSync, mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';

const MOD = '/data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/node-addon-system/lib/flock.js';
const base = '/data/data/com.termux/files/home/.flocktest';
rmSync(base, { recursive: true, force: true });
mkdirSync(base, { recursive: true });
const p = join(base, 'session.lock');

const { tryLockExclusive } = await import(pathToFileURL(MOD).href);
console.log('import ok:', MOD.split('/').slice(-3).join('/'));

const fd1 = openSync(p, 'w');
await tryLockExclusive(fd1);
console.log('① 首次加锁           -> 成功（未抛异常）');

const fd2 = openSync(p, 'w');
try {
  await tryLockExclusive(fd2);
  console.log('② 二次加锁           -> !! 竟然成功了（互斥失败 ❌）');
} catch (e) {
  console.log(`② 二次加锁           -> 正确拒绝  code=${e.code} errno=${e.errno} syscall=${e.syscall}`);
}

closeSync(fd1);
const fd3 = openSync(p, 'w');
try {
  await tryLockExclusive(fd3);
  console.log('③ 关掉持锁 fd 后重取 -> 成功（释放语义正确 ✅）');
} catch (e) {
  console.log(`③ 关掉持锁 fd 后重取 -> 仍被拒 code=${e.code}  ❌ 说明锁没释放`);
}
closeSync(fd2);
closeSync(fd3);
rmSync(base, { recursive: true, force: true });
