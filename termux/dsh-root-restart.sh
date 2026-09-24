#!/system/bin/sh
# root 侧把 dsh 以 Termux 身份(uid 10541 + 完整附属组)重启/启动的辅助脚本。
# 关键：用户位置参数必须放在 -c 之前，否则实际以 root 运行（Uid: 0）。
#   su -g 10541 -G 3003 -c "..."         -> Uid: 0      ✗
#   su -g 10541 -G 3003 10541 -c "..."   -> Uid: 10541  ✓
TH=/data/data/com.termux/files/home
TP=/data/data/com.termux/files/usr
ACTION="${1:-restart}"
TG="3003 1004 1007 1011 1015 1028 1078 1079 3001 3002 3006 3009 3011 3012"
GARGS="-g 10541"
for g in $TG; do GARGS="$GARGS -G $g"; done

echo "=== 部署 ==="
cp -f /data/local/tmp/dsh-autostart.sh /data/adb/service.d/dsh-autostart.sh
chown 0:0 /data/adb/service.d/dsh-autostart.sh
chmod 755 /data/adb/service.d/dsh-autostart.sh
sh -n /data/adb/service.d/dsh-autostart.sh && echo "  自启脚本语法 OK"
cp -f /data/local/tmp/dsh-go.sh "$TH/dsh-go.sh"
chown 10541:10541 "$TH/dsh-go.sh"
chmod 755 "$TH/dsh-go.sh"
su $GARGS 10541 -c "$TP/bin/bash -n $TH/dsh-go.sh" && echo "  dsh-go.sh 语法 OK"

echo
echo "=== 清理可能被 root 写坏属主的文件（若无则无输出）==="
find "$TH/.dsh" -user root -exec chown 10541:10541 {} \; 2>/dev/null
find "$TH/.dsh" -user root 2>/dev/null | head -5

echo
echo "=== root 侧先清掉可能在跑的旧实例（含 uid:0 的残留，10541 杀不掉它们）==="
pkill -f "bin/dsh web" 2>/dev/null
sleep 2
pkill -9 -f "bin/dsh web" 2>/dev/null
sleep 1
pgrep -f "bin/dsh web" >/dev/null && echo "  仍有残留" || echo "  已清"

echo
echo "=== 以 uid 10541 + 完整组 $ACTION dsh ==="
su $GARGS 10541 -c "$TP/bin/bash $TH/dsh-go.sh $ACTION"

echo
echo "=== 复核运行中的 dsh 进程身份 ==="
for p in $(pgrep -f "bin/dsh web"); do
    echo "  pid=$p"
    grep -E '^(Uid|Groups)' "/proc/$p/status" 2>/dev/null | sed 's/^/    /'
done
