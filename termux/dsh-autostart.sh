#!/system/bin/sh
# =============================================================================
# dsh-autostart.sh —— 开机自启 DeepSeek Harness Web UI + 虚拟副屏
#
# 放在 /data/adb/service.d/ 下，由 KernelSU 在开机 service 阶段以 root 执行。
#
# [教训一] 勿改回同步调用 run_daemon.sh
#   run_daemon.sh 结尾是 `exec /system/bin/app_process ... com.agent.DaemonMain ...`，
#   那是**前台常驻守护进程，永不返回**；同步调用会把本脚本永久卡死在该行。
#   正确做法：用模块自带的 `vd start`（内部 nohup 后台化 + 轮询状态文件 + 幂等）。
#
# [教训二] 起 Termux 侧进程必须补附属组（2026-09-24 实测定性）
#   KernelSU 的 `su <uid>` **只设 uid/gid，不设 supplementary groups**
#   （实测 `su 10541 -c 'grep Groups /proc/self/status'` → Groups: 为空）。
#   而 Android 的 DNS 走 /dev/socket/dnsproxyd，该 socket 是 `root:inet 660`，
#   必须属于 **inet 组(3003)** 才能连。没有组 ⟹ 连不上 dnsproxyd ⟹
#   **所有域名解析失败（ENOTFOUND）**，但裸 IP 仍可连 —— 于是 dsh 的模型请求
#   全部报 connection error / request timeout，极难排查。
#   实测铁证（同一台机、同一条命令）：
#     su 10541                -> HTTP=000 dns=0.000000s   Groups:（空）  ✗
#     su -g 10541 -G 3003     -> HTTP=401 dns=0.001273s   Groups: 3003   ✓
#   ⚠️ 语法坑：用户位置参数必须在 -c 之前！
#     `su -g 10541 -G 3003 -c "..."`   -> 实际仍是 root（Uid: 0）
#     `su -g 10541 -G 3003 10541 -c "..."` -> Uid: 10541 + Groups: 3003  ✓
#   注意：Android 的 `id`（toybox）**会骗人**（会显示主组名，看不出附属组为空），
#         判断只能看 `/proc/self/status` 的 `Groups:` 行。
#
# [教训三] 唤醒 Termux App 进程（辅助，非充分）
#   让 AMS 起一次 App 进程有助于网络登记；但实测它**不是充分条件**（见教训二），
#   保留它是为了顺带把电池白名单/待机桶设好。
#
# 验收：
#   curl -s http://127.0.0.1:3070/api/status                          # {"status":"running",...}
#   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3080/    # 401
#   cat /data/data/com.termux/files/home/dsh-autostart.log
# =============================================================================
MOD=/data/adb/modules/agent_mobile_use
VD="$MOD/system/bin/vd"
TH=/data/data/com.termux/files/home
TP=/data/data/com.termux/files/usr
RLOG=/data/local/tmp/dsh-autostart.log
TERMUX_ACT=com.termux/com.termux.app.TermuxActivity

# Termux App 自身的附属组（run-as com.termux id 实测所得，去掉 50541）
TG="3003 1004 1007 1011 1015 1028 1078 1079 3001 3002 3006 3009 3011 3012"
GARGS="-g 10541"
for g in $TG; do GARGS="$GARGS -G $g"; done

log() { echo "[$(date '+%F %T')] $*" >> "$RLOG"; }

# 开机后多久开始跑 —— 区分「真·开机自启」与「手动空跑」的判据
UP0=$(cut -d. -f1 /proc/uptime 2>/dev/null)
echo "===== dsh-autostart $(date '+%F %T') pid=$$ uptime=${UP0:-?}s =====" > "$RLOG"

# --- 等系统完全启动 ---
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 180 ]; do
    sleep 2
    i=$((i + 1))
done
log "boot_completed=1 (waited ${i}x2s), sleep 20"
sleep 20

# --- 1) 拉起虚拟副屏（幂等；内部顺带起 vd_server 并 nohup 后台化守护进程）---
log "--- vd start ---"
if [ -x "$VD" ]; then
    sh "$VD" start >> "$RLOG" 2>&1
    log "vd start rc=$?"
else
    log "!! 找不到 $VD"
fi

# --- 2) 让 Termux 常驻 + 唤醒 App 进程（辅助措施）---
log "--- 让 Termux 常驻（电池优化白名单 + 待机桶 active）---"
dumpsys deviceidle whitelist +com.termux >> "$RLOG" 2>&1
am set-standby-bucket com.termux active >> "$RLOG" 2>&1

log "--- 唤醒 Termux App ---"
am start -W -n "$TERMUX_ACT" >> "$RLOG" 2>&1
j=0
while [ -z "$(pidof com.termux)" ] && [ $j -lt 30 ]; do
    sleep 1
    j=$((j + 1))
done
log "com.termux pid=$(pidof com.termux) (waited ${j}s)"

# --- 3) 出网自检：必须带附属组，且必须用【域名】而不是裸 IP（否则查不出 DNS 故障）---
log "--- 出网自检（带附属组）---"
NET=FAIL
n=0
while [ $n -lt 6 ]; do
    GOT=$(su $GARGS 10541 -c "grep Groups /proc/self/status" 2>/dev/null)
    code=$(su $GARGS 10541 -c "$TP/bin/curl -s -m 8 -o /dev/null -w '%{http_code}' https://api.deepseek.com/" 2>/dev/null)
    log "  #$n groups=[$GOT] HTTP=$code"
    case "$code" in
        200|401|403|404) NET=OK; break ;;
    esac
    n=$((n + 1))
    sleep 3
done
log "出网自检结果: $NET"

# 把 Termux 收进后台，避免开机后停在它界面上
input keyevent 3

# --- 4) 以 Termux uid + 完整附属组启动 dsh web ---
log "--- dsh-go.sh start (su $GARGS) ---"
if [ -x "$TP/bin/bash" ] && [ -f "$TH/dsh-go.sh" ]; then
    su $GARGS 10541 -c "$TP/bin/bash $TH/dsh-go.sh start" >> "$RLOG" 2>&1
    log "dsh-go rc=$?"
else
    log "!! 缺少 $TP/bin/bash 或 $TH/dsh-go.sh"
fi

# --- 5) 日志副本交给 Termux 侧（/data/local/tmp 对 uid 10541 不可读）---
cp -f "$RLOG" "$TH/dsh-autostart.log" 2>/dev/null
chown 10541:10541 "$TH/dsh-autostart.log" 2>/dev/null
chmod 644 "$TH/dsh-autostart.log" 2>/dev/null
log "done"
