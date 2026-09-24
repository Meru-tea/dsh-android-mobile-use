// 用 DSH 官方的 @deepseek-ai/dsh-agent-presets 发现器，按 DSH 自己的规则校验 mobile-use preset
// 能发现 = DSH 也能发现；broken 字段为空 = 插件行全部可解析，不会出现 "failed to mount"
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

const DSH = '/data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh';
const HOME = process.env.HOME;

const mod = await import(pathToFileURL(join(DSH, 'node_modules/@deepseek-ai/dsh-agent-presets/lib/index.js')).href);
const { discoverPresets, SHIPPED_PRESET_ROOT } = mod;
// index.js 只再导出了 COMPOSITION_FILE/discoverPresets/scanRoot/SHIPPED_PRESET_ROOT，
// USER_PRESET_DIR 需从 ./discovery 取，这里直接按源码 discovery.js:48 的值硬编码
const USER_PRESET_DIR = '.agent-presets';

console.log('USER_PRESET_DIR =', USER_PRESET_DIR);
console.log('SHIPPED_PRESET_ROOT =', SHIPPED_PRESET_ROOT);

const harnessBase = pathToFileURL(DSH + '/').href;
console.log('harnessBase =', harnessBase);
console.log('');

const roots = [
  { path: join(HOME, '.dsh', USER_PRESET_DIR), trust: 'user' },
  { path: SHIPPED_PRESET_ROOT, trust: 'shipped' },
];

const rows = await discoverPresets(roots, harnessBase);
console.log(`发现 ${rows.length} 个 preset：`);
console.log('');
for (const r of rows) {
  const meta = `${r.name ?? '(无名)'} / order=${r.order ?? '-'}`;
  console.log(`- id=${r.id}`);
  console.log(`  trust  = ${r.trust}`);
  console.log(`  meta   = ${meta}`);
  console.log(`  path   = ${r.path}`);
  console.log(`  状态   = ${r.broken ? 'BROKEN >> ' + r.broken : 'OK（可挂载）'}`);
  console.log('');
}

const mu = rows.find(r => r.id === 'mobile-use');
console.log('==> mobile-use 结论:', mu ? (mu.broken ? '存在但损坏：' + mu.broken : '存在且可挂载 ✅') : '未发现 ❌');
process.exit(mu && !mu.broken ? 0 : 1);
