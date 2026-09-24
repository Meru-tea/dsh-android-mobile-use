#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# install.sh —— DSH Android 手机助手：端侧一键部署（在 Termux 里执行）
#
#   bash install.sh              # 完整部署
#   bash install.sh --step 10    # 只跑某一步
#   bash install.sh --list       # 看步骤清单
#
# 前置条件（必须先满足，脚本会检查）：
#   1. 已 root（KernelSU / SukiSU / APatch 任一），且 `su` 可用
#   2. 已装 Vector（或 LSPosed）与底座模块 agent-mobile-use，且其 3070 网关在跑
#   3. Termux 本身可用（建议用 GitHub Release 的 debug 签名 APK —— run-as 需要它）
#   4. 有网（脚本会把 Termux 源换成清华源）
#
# 每一步都是**幂等**的：可重复执行。
# =============================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX=/data/data/com.termux/files/usr
HOME_DIR=/data/data/com.termux/files/home
export PREFIX HOME_DIR
export PATH="$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib"
export LANG=C.UTF-8
export TMPDIR="$PREFIX/tmp"
mkdir -p "$TMPDIR"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✓ %s\033[0m\n' "$*"; }
warn() { printf '    \033[33m! %s\033[0m\n' "$*"; }
die()  { printf '    \033[31m✗ %s\033[0m\n' "$*"; exit 1; }

# --- dsh 版本探测 / 比较（步骤 30 用来判断 workflow 插件该用哪个名字）---------
dsh_version() {
  local pkg="$PREFIX/lib/node_modules/@deepseek-ai/dsh/package.json"
  [ -f "$pkg" ] || return 1
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pkg" | head -1
}
# $1 >= $2 ?  （sort -V 在 Toybox/BusyBox 上也可用）
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1)" = "$1" ]; }

STEPS="10 15 20 25 30 40"
step_desc() {
  case "$1" in
    10) echo "装 Termux 依赖（清华源 + node/python/clang/cmake…）并安装 DSH" ;;
    15) echo "修 npm/npx 的坏 shebang（Android 没有 /usr/bin/env）" ;;
    20) echo "给 node-addon-system 打 Android flock 补丁" ;;
    25) echo "安装 mobile-use 预设到 ~/.dsh/.agent-presets/mobile-use/" ;;
    30) echo "按 dsh 版本校正预设的 workflow 插件名，并用 DSH 官方发现器复校可挂载性" ;;
    40) echo "部署运行期脚本（dsh-go.sh / dsh-root-restart.sh / 开机自启）" ;;
  esac
}

[ "${1:-}" = "--list" ] && { echo "步骤："; for s in $STEPS; do printf '  %-3s %s\n' "$s" "$(step_desc $s)"; done; exit 0; }

ONLY=""
[ "${1:-}" = "--step" ] && ONLY="${2:-}"

run_step() {
  [ -n "$ONLY" ] && [ "$ONLY" != "$1" ] && return 0
  say "[$1/40] $(step_desc $1)"
  case "$1" in
    10)
      bash "$HERE/10-dsh-termux-install-tuna.sh" || die "步骤 10 失败"
      ;;
    15)
      bash "$HERE/15-fix-npm-shebang.sh" || die "步骤 15 失败"
      ;;
    20)
      local tgt="$PREFIX/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/node-addon-system/lib/flock.js"
      [ -f "$tgt" ] || die "找不到 $tgt（DSH 装好了吗？跑 bash install.sh --step 10）"
      if grep -q "platform === 'android'" "$tgt" 2>/dev/null; then
        ok "flock.js 已含 Android 分支，跳过"
      else
        cp -f "$tgt" "$tgt.orig-backup" 2>/dev/null
        # 优先用补丁；补丁打不上（版本漂移）时退化为直接替换整文件
        if ( cd "$PREFIX/lib/node_modules/@deepseek-ai/dsh" && \
             git -c core.autocrlf=false apply -p1 --directory=. \
                 "$HERE/../patches/0001-node-addon-system-android-flock.patch" 2>/dev/null ); then
          ok "已用补丁方式打上"
        elif [ -f "$HERE/../patches/flock.js.patched" ]; then
          warn "补丁未直接命中，改为整文件替换（原文件已备份为 flock.js.orig-backup）"
          cp -f "$HERE/../patches/flock.js.patched" "$tgt"
        else
          die "补丁打不上、也没带 .patched 文件；请提 Issue"
        fi
      fi
      # 打完再验一次语义
      node "$HERE/tools/verify-flock.mjs" || die "flock 补丁语义验证失败"
      ;;
    25)
      bash "$HERE/25-install-preset.sh" || die "步骤 25 失败"
      ;;
    30)
      # 这一步是**版本适配**，不是修上游 bug —— workflow 插件名随 dsh 版本变：
      #   dsh <= 0.1.5-rc.3   -> @deepseek-ai/dsh-workflow-worker-thread
      #   dsh >= 0.1.6-alpha.1 -> @deepseek-ai/dsh-workflow-ptc   (上游 HEAD 用的就是这个)
      # 改名方向是 worker-thread -> ptc，发生在 0.1.6-alpha.1 边界。
      local y="$HOME_DIR/.dsh/.agent-presets/mobile-use/agent.cordis.yml"
      [ -f "$y" ] || die "找不到 $y（先跑 --step 25）"

      local v; v="$(dsh_version || true)"
      if [ -z "$v" ]; then
        warn "探测不到 dsh 版本，默认按旧线（<= 0.1.5-rc.3）处理"
        v="0.1.5-rc.3"
      fi
      say "dsh 版本：$v"

      if ver_ge "$v" "0.1.6-alpha.1"; then
        # 新线：上游原样就是对的。若之前被改成了 -worker-thread，这里改回来。
        if grep -q "dsh-workflow-worker-thread" "$y" 2>/dev/null; then
          cp -f "$y" "$y.bak"
          sed -i "s|@deepseek-ai/dsh-workflow-worker-thread|@deepseek-ai/dsh-workflow-ptc|g" "$y"
          warn "dsh >= 0.1.6：已把插件名从 -worker-thread 改回 -ptc（原文件备份为 agent.cordis.yml.bak）"
        else
          ok "dsh >= 0.1.6：插件名 -ptc 正确，无需改动"
        fi
      else
        # 旧线：需要改成 -worker-thread
        if grep -q "dsh-workflow-worker-thread" "$y" 2>/dev/null; then
          ok "dsh <= 0.1.5-rc.3：插件名已是 -worker-thread，跳过"
        else
          cp -f "$y" "$y.bak"
          sed -i "s|@deepseek-ai/dsh-workflow-ptc|@deepseek-ai/dsh-workflow-worker-thread|g" "$y"
          ok "dsh <= 0.1.5-rc.3：已改为 -worker-thread（原文件备份为 agent.cordis.yml.bak）"
        fi
      fi
      node "$HERE/tools/check-preset-mount.mjs" || die "预设不可挂载，请修好再继续"
      ;;
    40)
      cp -f "$HERE/dsh-go.sh" "$HOME_DIR/dsh-go.sh"; chmod 755 "$HOME_DIR/dsh-go.sh"
      cp -f "$HERE/dsh-root-restart.sh" "$HOME_DIR/dsh-root-restart.sh"; chmod 755 "$HOME_DIR/dsh-root-restart.sh"
      ok "已装 ~/dsh-go.sh 与 ~/dsh-root-restart.sh"
      if [ -d /data/adb/service.d ]; then
        cp -f "$HERE/dsh-autostart.sh" /data/adb/service.d/dsh-autostart.sh 2>/dev/null \
          && ok "开机自启已装到 /data/adb/service.d/" \
          || warn "写 /data/adb/service.d 需要 root —— 请用: su -c 'cp \$HERE/dsh-autostart.sh /data/adb/service.d/'"
      fi
      ;;
  esac
}

say "DSH Android 手机助手 · 端侧部署"
echo "    Termux: $PREFIX"
command -v node >/dev/null 2>&1 && echo "    Node:   $(node -v)" || echo "    Node:   （尚未安装）"
command -v su   >/dev/null 2>&1 && echo "    su:     可用" || warn "su 不可用 —— 步骤 40 的开机自启会失败"

for s in $STEPS; do run_step "$s"; done

say "完成"
cat <<'EOF'
    启动:      bash ~/dsh-go.sh start
    看状态:    bash ~/dsh-go.sh status      ← 第一段就是「附属组 + 出网」自检
    开机自启:  已装 /data/adb/service.d/dsh-autostart.sh（重启后零操作）
    然后:      打开 http://127.0.0.1:3080/?token=… ，右上角预设切到 mobile-use

    踩坑与排查: docs/pitfalls.md  docs/troubleshooting.md
EOF
