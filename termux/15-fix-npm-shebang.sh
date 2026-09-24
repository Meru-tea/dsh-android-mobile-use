#!/data/data/com.termux/files/usr/bin/bash
# 修复 npm 降级后产生的坏 shebang。
# 背景: Termux 的 npm/npx 是指向 ../lib/node_modules/npm/bin/*-cli.js 的软链,
#       这些 js 首行是 `#!/usr/bin/env node`, 而 Android 根本没有 /usr/bin/env,
#       于是 exec 直接报 "bad interpreter: No such file or directory"。
#       termux-fix-shebang 只把 */bin/* 改写成 $PREFIX/bin/*, 会把 env 原样留下 -> 仍然失效。
#       所以这里直接把 shebang 换成 node 的绝对路径。
# 说明: 每次 `npm install -g <pkg>` 之后都会新增同样毛病的 bin, 本脚本可重复执行(幂等)。
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:$PATH
NODE="$PREFIX/bin/node"
N=0

fix_one() {
  f="$1"
  [ -n "$f" ] || return 0
  [ -e "$f" ] || return 0
  # 软链必须追到真实文件, 否则 sed -i 会把软链本身替换成普通文件
  rp=$(realpath "$f" 2>/dev/null) || rp="$f"
  [ -f "$rp" ] || return 0
  first=$(head -n 1 "$rp" 2>/dev/null)
  case "$first" in
    '#!'*'node'*)
      case "$first" in
        "#!$NODE"|"#!$NODE "*) return 0 ;;   # 已是绝对路径, 跳过
      esac
      sed -i "1s|^#!.*|#!$NODE|" "$rp"
      echo "  fixed  $(basename "$f") -> $(head -n 1 "$rp")"
      N=$((N+1))
      ;;
    *) : ;;   # 非 node 解释器(sh/python/...)一律不动
  esac
}

echo "=== [A] \$PREFIX/bin 下所有指向 *.js 的启动器 ==="
for f in "$PREFIX"/bin/*; do
  rp=$(realpath "$f" 2>/dev/null) || continue
  case "$rp" in
    *.js|*.cjs|*.mjs) fix_one "$f" ;;
  esac
done

echo "=== [B] \$PREFIX/lib/node_modules 下所有 .bin/* ==="
find "$PREFIX/lib/node_modules" -maxdepth 5 -path '*/.bin/*' 2>/dev/null | while read -r f; do
  fix_one "$f"
done

echo "=== verify ==="
echo "node : $($NODE --version 2>&1)"
echo "npm  : $($PREFIX/bin/npm --version 2>&1 | tail -1)"
echo "npx  : $($PREFIX/bin/npx --version 2>&1 | tail -1)"
echo "(已修 $N 个文件)"
