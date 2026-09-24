#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# dsh-go.sh —— DeepSeek Harness Web UI 启停/信息（Termux 侧唯一入口）
#
#   bash ~/dsh-go.sh          启动（默认）
#   bash ~/dsh-go.sh restart  重启
#   bash ~/dsh-go.sh stop     停止
#   bash ~/dsh-go.sh status   查看状态
#   bash ~/dsh-go.sh url      只打印访问地址
#
# 说明：token 每次启动都会变，但浏览器 cookie 的签名密钥持久化在
#       $DSH_HOME/.credentials.yaml，且 cookie 只绑定 host:port（不绑 token）。
#       所以【访问过一次带 token 的地址后，之后用裸地址 http://127.0.0.1:3080/
#       就能直接进，重启 dsh 也不影响】（cookie 有效期 30 天）。
#
# ⚠️ 从 Termux 里正常执行本脚本即可（Termux App 的 shell 自带完整附属组）。
#    若是**从 root 侧**（adb / service.d）拉起，必须补附属组，否则 DNS 全挂：
#      su -g 10541 -G 3003 10541 -c "$PREFIX/bin/bash $HOME/dsh-go.sh start"
#    （详见本文件里 groups_check() 的注释）
# =============================================================================
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib
export LANG=C.UTF-8
export TMPDIR=$PREFIX/tmp
mkdir -p "$TMPDIR"

export AGENT_VD_SERVER="http://127.0.0.1:3070"
export DSH_HOME="$HOME/.dsh"
export DSH_TELEMETRY_DISABLED=1
export DSH_PERMISSION_MODE=danger-full-access

PORT=3080
URLFILE="$HOME/dsh-url.txt"
LOG="$HOME/web.log"

stop_dsh() {
  pkill -f "dsh web" 2>/dev/null
  sleep 3
  if pgrep -f "dsh web" >/dev/null 2>&1; then
    pkill -9 -f "dsh web" 2>/dev/null
    sleep 1
  fi
  pgrep -f "dsh web" >/dev/null 2>&1 && echo "  ✗ 仍有残留进程" || echo "  ✓ 已停止"
}

start_dsh() {
  echo "--- 启动前出网自检 ---"
  net_check || echo "  (仍继续启动；但模型请求会超时)"
  stop_dsh
  cd "$HOME" || exit 1
  : > "$LOG"
  nohup dsh web --port "$PORT" --no-open > "$LOG" 2>&1 &
  # 等 token 出现（最多 30s）
  i=0
  while [ $i -lt 30 ]; do
    sleep 1
    grep -q "token=" "$LOG" 2>/dev/null && break
    i=$((i+1))
  done
  TOKEN_URL=$(grep -o "http://127.0.0.1:$PORT/?token=[A-Za-z0-9_-]*" "$LOG" | head -1)
  if [ -z "$TOKEN_URL" ]; then
    echo "  ✗ 启动失败，日志末尾："
    tail -15 "$LOG"
    exit 1
  fi
  {
    echo "# DeepSeek Harness Web UI  ($(date '+%F %T'))"
    echo "# 首次访问请用下面这条（种 cookie）；以后直接用书签里的裸地址即可"
    echo "$TOKEN_URL"
    echo "http://127.0.0.1:$PORT/"
  } > "$URLFILE"
  echo "  ✓ 已启动 (端口 $PORT)"
  echo "  首次访问: $TOKEN_URL"
  echo "  以后书签: http://127.0.0.1:$PORT/"
  echo "  地址也存到了: $URLFILE"
}

show_url() { [ -f "$URLFILE" ] && cat "$URLFILE" || echo "(还没启动过，先跑 bash ~/dsh-go.sh)"; }

# 出网自检。注意必须用【域名】而不是裸 IP —— 因为最常见的一类故障是
# "裸 IP 能连、域名解析不了"，只测 IP 永远查不出来。
net_check() {
  code=$(curl -s -m 8 -o /dev/null -w '%{http_code}' https://api.deepseek.com/ 2>/dev/null)
  case "$code" in
    200|401|403|404) echo "  ✓ 出网正常 (api.deepseek.com HTTP=$code)" ; return 0 ;;
    *) echo "  ✗ 出网不通 (HTTP=$code) —— dsh 的模型请求会 connection error / timeout"
       groups_check || true
       return 1 ;;
  esac
}

# 检查本进程的附属组。KernelSU 的 `su <uid>` **只设 uid/gid、不设附属组**，
# 而 /dev/socket/dnsproxyd 是 root:inet 660 —— 缺 inet(3003) 就连不上它，
# 表现为「裸 IP 能连、所有域名 ENOTFOUND」。
# ⚠️ 只能看 /proc/self/status 的 Groups 行：Android 的 `id`(toybox) 会显示主组名，
#    附属组为空时照样看着"有组"，会骗人。
groups_check() {
  # 注意 print $2 只会取到第一个组、把列表截断 —— 必须取整行剩余部分；
  # 且要用 /proc/$$/status（self 会指到 awk 自己）
  g=$(awk '/^Groups:/{sub(/^Groups:[ \t]*/,""); print}' /proc/$$/status 2>/dev/null)
  if [ -z "$g" ]; then
    echo "    根因: 本进程附属组为空 → 连不上 dnsproxyd → 域名解析全失败"
    echo "    修法: su -g 10541 -G 3003 10541 -c \"\$PREFIX/bin/bash \$HOME/dsh-go.sh restart\""
    return 1
  fi
  case " $g " in
    *" 3003 "*) echo "    (附属组含 inet:3003 正常)" ; return 0 ;;
  esac
  echo "    根因: 附属组里没有 inet(3003) → DNS 会失败（当前: $g）"
  echo "    修法: su -g 10541 -G 3003 10541 -c \"\$PREFIX/bin/bash \$HOME/dsh-go.sh restart\""
  return 1
}

status_all() {
  echo "--- 进程身份 / 附属组 ---"
  groups_check
  echo "--- 出网自检 ---"
  net_check
  echo "--- dsh web 进程 ---"
  pgrep -f "dsh web" >/dev/null 2>&1 && pgrep -af "dsh web" | head -3 || echo "  未运行"
  echo "--- 3080 端口 ---"
  curl -s -m 4 -o /dev/null -w "  HTTP=%{http_code}  (401=没带 cookie 属正常; 200=正常)\n" "http://127.0.0.1:$PORT/" || echo "  连不上"
  echo "--- 3070 网关（副屏）---"
  curl -s -m 5 "http://127.0.0.1:3070/api/status" || echo "  连不上（副屏可能没建）"
  echo
  echo "--- 开机自启 ---"
  echo "  注: /data/adb 对 Termux 不可读，故不看脚本本身，改用【日志时间 vs 开机时间】判定"
  UP=$(cut -d. -f1 /proc/uptime 2>/dev/null)
  NOW=$(date +%s)
  BOOT=$((NOW - ${UP:-0}))
  echo "  本次开机于: $(uptime -s 2>/dev/null || echo "约 $(( ${UP:-0} / 60 )) 分钟前")（已运行 $(( ${UP:-0} / 60 )) 分 $(( ${UP:-0} % 60 )) 秒）"
  if [ -f "$HOME/dsh-autostart.log" ]; then
    MT=$(stat -c %Y "$HOME/dsh-autostart.log" 2>/dev/null)
    UP0=$(head -1 "$HOME/dsh-autostart.log" | grep -o 'uptime=[0-9]*s' | tr -dc '0-9')
    if [ -n "$MT" ] && [ "$MT" -ge "$BOOT" ]; then
      if [ -n "$UP0" ] && [ "$UP0" -le 120 ]; then
        echo "  自启状态: ✅ 真·开机自启已生效（脚本在开机后 ${UP0}s 起跑）"
      elif [ -n "$UP0" ]; then
        echo "  自启状态: ✓ 本次开机内跑过，但起跑于开机后 ${UP0}s —— 看形态是【手动/空跑】而非开机触发"
      else
        echo "  自启状态: ✓ 本次开机内跑过（旧版日志无 uptime 标记，无法判断是否开机触发）"
      fi
    else
      echo "  自启状态: ⚠ 日志来自更早（$(date -d "@${MT:-0}" '+%F %T' 2>/dev/null)），本次开机未触发"
    fi
    echo "  日志末尾:"
    tail -6 "$HOME/dsh-autostart.log" | sed 's/^/    /'
  else
    echo "  自启状态: ⚠ 从未触发（无日志文件）"
    echo "  排查: /data/adb/service.d/dsh-autostart.sh 是否在位；KernelSU 的 service.d 是否启用"
  fi
  echo
  echo "--- 访问地址 ---"
  show_url
}

case "${1:-start}" in
  start)   start_dsh ;;
  restart) start_dsh ;;
  stop)    stop_dsh ;;
  url)     show_url ;;
  status)  status_all ;;
  *)       echo "用法: bash ~/dsh-go.sh [start|restart|stop|status|url]" ;;
esac
