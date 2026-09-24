#!/usr/bin/env python3
"""体检：本仓库所有文本文件必须是 LF、无 CR；shell 脚本语法可解析。

入库策略（与 .gitignore 保持一致）：
  - *.orig / *.upstream 是上游原件，只用于生成补丁，不入库 → 跳过
  - *.fixed / *.patched 是「打补丁后可直接覆盖」的成品，**必须入库**
    （补丁因版本漂移打不上时的兜底），因此也要参与体检
"""
import os, sys, subprocess, fnmatch

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TEXT_EXT = ('.md', '.sh', '.mjs', '.js', '.yml', '.yaml', '.patch', '.txt', '')
SKIP_DIRS = {'.git', 'node_modules', '__pycache__'}
SKIP_PAT = ['*.orig', '*.upstream', '*.bak', '*-backup']
# 成品文件后缀：剥离后再按类型判定（customize.sh.fixed → customize.sh）
PRODUCT_SUFFIX = ('.fixed', '.patched')


def effective_name(fn):
    """把 a.sh.fixed / a.js.patched 还原成 a.sh / a.js，便于按真实类型判定。"""
    for suf in PRODUCT_SUFFIX:
        if fn.endswith(suf):
            return fn[: -len(suf)]
    return fn


bad_cr, bad_sh, n = [], [], 0
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for fn in filenames:
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, ROOT).replace('\\', '/')
        if any(fnmatch.fnmatch(fn, pat) for pat in SKIP_PAT):
            continue
        eff = effective_name(fn)
        if not (eff.endswith(TEXT_EXT) or eff == 'LICENSE'):
            continue
        b = open(p, 'rb').read()
        n += 1
        if b.count(13):
            bad_cr.append((rel, b.count(13)))
        if eff.endswith('.sh'):
            r = subprocess.run(['sh', '-n', p], capture_output=True)
            if r.returncode != 0:
                bad_sh.append((rel, r.stderr.decode(errors='replace').strip()[:120]))

print(f'扫描 {n} 个文本文件')
if bad_cr:
    print('\n[FAIL] 含 CR（应为纯 LF）:')
    for r, c in bad_cr:
        print(f'   {r}  CR={c}')
else:
    print('[ok]   全部为纯 LF')

if bad_sh:
    print('\n[FAIL] shell 语法错误:')
    for r, e in bad_sh:
        print(f'   {r}\n      {e}')
else:
    print('[ok]   所有 .sh（含 .fixed/.patched 成品）通过 sh -n')

sys.exit(1 if (bad_cr or bad_sh) else 0)