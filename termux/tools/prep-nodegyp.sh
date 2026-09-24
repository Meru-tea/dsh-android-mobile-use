#!/data/data/com.termux/files/usr/bin/bash
# 解决 dsh 安装时 node-pty 原生编译失败：
#  1) node-pty 无 android-arm64 预编译产物 -> 必须用 node-gyp 本地编译
#  2) node-pty 的 install 脚本调用裸 `node-gyp`，而 Termux 的 $PREFIX/bin 里没有它，
#     npm 也不会把 npm 自带的 node-gyp 加进生命周期脚本的 PATH
#     （Android 上 dash 找不到命令时会误报 "Permission denied"，极具迷惑性）
#  3) node-gyp 编译前要下 Node 头文件，nodejs.org 在国内常不通 -> 走 npmmirror
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib
export LANG=C.UTF-8

NGY_JS="$PREFIX/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js"

echo "### 0. 验证 dash 的误导性报错"
sh -c 'a-command-that-does-not-exist-xyz' 2>&1
echo

echo "### 1. 暴露 node-gyp 到 \$PREFIX/bin"
if [ ! -f "$NGY_JS" ]; then
  echo "!! 找不到 npm 自带的 node-gyp: $NGY_JS"
  echo "   搜索一下:"; find "$PREFIX/lib/node_modules/npm" -maxdepth 4 -name 'node-gyp.js' 2>/dev/null
  exit 1
fi
chmod 755 "$NGY_JS"
ln -sf "$NGY_JS" "$PREFIX/bin/node-gyp"
chmod 755 "$PREFIX/bin/node-gyp" 2>/dev/null
echo "  -> $(ls -la "$PREFIX/bin/node-gyp")"
echo "  node-gyp: $(node-gyp --version 2>&1)"
echo

echo "### 2. 预热 Node 头文件缓存 (走 npmmirror)"
export npm_config_disturl="https://npmmirror.com/mirrors/node"
NV="$(node -p 'process.versions.node')"
echo "  node=$NV  disturl=$npm_config_disturl"
echo "  --- node-gyp install ---"
node-gyp install --verbose 2>&1 | tail -25
echo "  rc=$?"
echo

echo "### 3. 检查头文件"
GP="$HOME/.cache/node-gyp/$NV/include/node/common.gypi"
if [ -f "$GP" ]; then
  echo "  OK: $GP"
else
  echo "  !! 仍缺失: $GP"
  ls -la "$HOME/.cache/node-gyp/" 2>&1
  exit 1
fi
echo
echo "### 4. 预打 common.gypi 补丁 (android_ndk_path 未定义 -> 定义为空)"
export DSH_GYPI="$GP"
node <<'JS'
const fs = require("node:fs");
const p = process.env.DSH_GYPI;
let s = fs.readFileSync(p, "utf8");
if (s.includes("'android_ndk_path%'")) { console.log("  gypi: 已打过补丁, 跳过"); process.exit(0); }
if (!s.includes("'variables': {")) { console.log("  gypi: 未找到 variables 锚点"); process.exit(1); }
s = s.replace("'variables': {", "'variables': {\n    'android_ndk_path%': '',", 1);
fs.writeFileSync(p, s);
console.log("  gypi: 补丁已应用 -> " + p);
JS
echo
echo "### 5. 编译链自检"
for c in node npm node-gyp python make clang cmake ninja; do
  printf '  %-10s %s\n' "$c" "$(command -v "$c" 2>/dev/null || echo '(缺)')"
done
