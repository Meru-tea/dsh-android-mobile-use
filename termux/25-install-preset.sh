#!/data/data/com.termux/files/usr/bin/bash
# 装 mobile-use preset 到 dsh 的 agent-presets 目录
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib
export LANG=C.UTF-8

echo "### dsh 版本"
dsh --version 2>&1 | tail -3
echo
echo "### preset 包结构"
unzip -l "$HOME/dsh-preset-mobile-use-v1.3.5.zip" 2>&1 | head -30
echo
echo "### 安装到 ~/.dsh/.agent-presets/mobile-use/"
mkdir -p "$HOME/.dsh/.agent-presets/mobile-use"
unzip -o -j "$HOME/dsh-preset-mobile-use-v1.3.5.zip" 'preset/mobile-use/*' \
  -d "$HOME/.dsh/.agent-presets/mobile-use/" 2>&1 | tail -15
echo
echo "### 落位结果"
ls -la "$HOME/.dsh/.agent-presets/mobile-use/" 2>&1
echo
echo "### ~/.dsh 树"
find "$HOME/.dsh" -maxdepth 3 2>&1 | head -20
