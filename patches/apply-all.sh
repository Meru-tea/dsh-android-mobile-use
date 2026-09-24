#!/usr/bin/env bash
# =============================================================================
# apply-all.sh —— 一次性把本仓库的上游补丁打到对应上游的工作树里
#
# 用法（在你 clone 好的某个上游仓库根目录执行）：
#   bash /path/to/patches/apply-all.sh
#
# ⚠️ 本机（Windows）core.autocrlf 默认为 true —— 一定要显式关掉，
#    否则补丁应用后会把 LF 写成 CRLF。脚本里已统一用 -c core.autocrlf=false。
#
# ⚠️ 0002 是**版本条件补丁**（仅 dsh <= 0.1.5-rc.3 需要）。
#    本脚本会自动探测 dsh 版本：>= 0.1.6 时**跳过 0002**，因为那两个版本的
#    workflow 插件名不同（详见 patches/0002-*.patch 的文件头与
#    D:\OnePlus\mobile-use\pr\FINDINGS-2026-09-24-version-floor.md）。
#    可用 DSH_VERSION=x.y.z 强制指定，或 DSH_VERSION=skip 直接不处理 0002。
# =============================================================================
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
GIT=(git -c core.autocrlf=false)

apply_one() {  # $1=补丁文件  $2=期望存在的目标  $3=用途说明
  local patch="$HERE/$1" target="$2" desc="$3"
  echo
  echo "==> $1"
  echo "    $desc"
  if [ ! -f "$patch" ]; then echo "    ! 找不到补丁文件"; return 1; fi
  if [ ! -e "$target" ]; then
    echo "    - 目标不存在，跳过（$target）"
    return 0
  fi
  if "${GIT[@]}" apply --check "$patch" 2>/dev/null; then
    "${GIT[@]}" apply "$patch"
    echo "    ✓ 已应用"
  elif "${GIT[@]}" apply --check --reverse "$patch" 2>/dev/null; then
    echo "    ✓ 已经打过了，跳过"
  else
    echo "    ✗ 打不上（上游版本可能已漂移）—— 请人工核对后提 Issue"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 探测 dsh 版本
# ---------------------------------------------------------------------------
detect_dsh_version() {
  if [ -n "${DSH_VERSION:-}" ]; then echo "$DSH_VERSION"; return 0; fi
  local pkg=""
  # 1) 环境变量指定包根
  if [ -n "${DSH_ROOT:-}" ] && [ -f "$DSH_ROOT/package.json" ]; then
    pkg="$DSH_ROOT/package.json"
  fi
  # 2) 交给 node 解析
  if [ -z "$pkg" ] && command -v node >/dev/null 2>&1; then
    pkg="$(node -e "try{console.log(require.resolve('@deepseek-ai/dsh/package.json'))}catch(e){}" 2>/dev/null || true)"
  fi
  # 3) Termux 常见安装位置
  if [ -z "$pkg" ]; then
    for c in \
      "/data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh/package.json" \
      "$HOME/.npm-global/lib/node_modules/@deepseek-ai/dsh/package.json" \
      "/usr/lib/node_modules/@deepseek-ai/dsh/package.json" ; do
      [ -f "$c" ] && { pkg="$c"; break; }
    done
  fi
  [ -n "$pkg" ] || { echo ""; return 0; }
  # 只取 version 字段，不引入 jq 依赖
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pkg" | head -1
}

# 版本比较：$1 >= $2 ?（用 sort -V，BusyBox/Toybox 的 sort 也支持 -V）
ver_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1)" = "$1" ]
}

DSH_V="$(detect_dsh_version || true)"
echo "探测到 dsh 版本：${DSH_V:-（未知）}"

SKIP_0002=""
if [ -z "$DSH_V" ]; then
  echo "  ! 探测不到 dsh 版本 —— 0002 是版本条件补丁，为安全起见**默认跳过**。"
  echo "    若你的 dsh 确实 <= 0.1.5-rc.3，请用 DSH_VERSION=0.1.5-rc.3 重跑。"
  SKIP_0002="1"
elif [ "$DSH_V" = "skip" ]; then
  SKIP_0002="1"
elif ver_ge "$DSH_V" "0.1.6-alpha.1"; then
  echo "  -> dsh >= 0.1.6：上游 HEAD 的写法本来就是对的，**跳过 0002**。"
  SKIP_0002="1"
else
  echo "  -> dsh <= 0.1.5-rc.3：需要 0002 做版本适配。"
fi

# ---------------------------------------------------------------------------
RC=0
apply_one 0001-node-addon-system-android-flock.patch \
  "node_modules/@deepseek-ai/node-addon-system/lib/flock.js" \
  "给 node-addon-system 的 flock.js 补 Android 分支" || RC=1

if [ -n "$SKIP_0002" ]; then
  echo
  echo "==> 0002-preset-workflow-plugin-name-dsh-le-0.1.5.patch"
  echo "    - 按版本判定跳过（见上方说明）"
else
  apply_one 0002-preset-workflow-plugin-name-dsh-le-0.1.5.patch \
    "preset/mobile-use/agent.cordis.yml" \
    "版本适配：把 workflow 插件名改成 dsh <= 0.1.5-rc.3 使用的 -worker-thread" || RC=1
fi

apply_one 0003-agent-mobile-use-lsposed-scope.patch \
  "customize.sh" \
  "修底座模块写 LSPosed 作用域的旧表结构 SQL" || RC=1

echo
if [ "$RC" = "0" ]; then
  echo "全部完成。"
else
  echo "有补丁未应用成功 —— 见上方输出。"
fi
exit "$RC"