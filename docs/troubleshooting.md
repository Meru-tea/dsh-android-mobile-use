# 排查手册（症状 → 定性 → 处置）

> 先跑这一条，它一次给出「附属组 + 出网 + 进程 + 端口 + 网关 + 开机自启」六项状态：
>
> ```bash
> bash ~/dsh-go.sh status
> ```
>
> 或者从电脑侧（手机连着 adb）：
> ```bash
> adb shell "su -c 'G=\"\"; for g in 3003 1004 1007 1011 1015 1028 1078 1079 3001 3002 3006 3009 3011 3012; do G=\"\$G -G \$g\"; done; su -g 10541 \$G 10541 -c \"bash \$HOME/dsh-go.sh status\"'"
> ```

---

## 症状速查表

| 症状 | 最可能原因 | 跳到 |
|---|---|---|
| `connection error` / `request timeout`，但**电脑上测同一个 API 正常** | 附属组缺失 → DNS 挂 | [A](#a-出网--dns) |
| `Could not resolve host: …` | 同上 | [A](#a-出网--dns) |
| 裸 IP 能连、域名不行 | 同上（**别去查路由**） | [A](#a-出网--dns) |
| DSH 里报 `preset "mobile-use" failed to mount` | 预设里有失效插件名 | [B](#b-预设挂载) |
| `flock is not supported on android-arm64` | node-addon-system 无 Android 支持 | [C](#c-flock) |
| `npm: /usr/bin/env: bad interpreter` | npm 降级后 shebang 变回上游版 | [D](#d-npm-自身坏掉) |
| `sh: 1: node-gyp: Permission denied` | 其实只是 PATH 里没有 | [E](#e-命令找不到被报成-permission-denied) |
| `EADDRINUSE 127.0.0.1:3080` | 旧实例没杀干净（uid 不同杀不掉） | [F](#f-eaddrinuse) |
| 3080 连不上 / 页面打不开 | dsh web 没起，或（从电脑侧）adb forward 掉了 | [G](#g-3080-打不开) |
| 虚拟副屏没了（`socket hang up` / 3070 无响应） | 重启后没重建副屏 | [H](#h-副屏没了) |
| 装 APK 报 `INSTALL_FAILED_VERIFICATION_FAILURE` | 安装校验拦截 | [I](#i-adb-装-apk-被拦) |
| 开机后 dsh 没起来 | 自启脚本卡住 / 没执行 | [J](#j-开机自启没生效) |

---

## A. 出网 / DNS

**📖 详见 [`pitfalls.md` 坑 1](pitfalls.md#坑-1头号su-uid-不设附属组--dns-全挂)** —— 这是本项目的头号坑。

三步定性：

```sh
U=https://api.deepseek.com/
su -c      "curl -s -m 8 -o /dev/null -w 'root   %{http_code} dns=%{time_namelookup} conn=%{time_connect}\n' $U"
su 10541 -c "curl -s -m 8 -o /dev/null -w 'appuid %{http_code} dns=%{time_namelookup} conn=%{time_connect}\n' $U"
su 10541 -c "curl -s -m 8 -o /dev/null -w 'bareip %{http_code}\n' http://223.5.5.5/"   # ★分水岭
su 10541 -c 'grep Groups /proc/self/status'                                             # ★看这行，别看 id
```

| 结果组合 | 结论 |
|---|---|
| root ✓ / appuid ✗ / **bareip ✓** | **附属组缺失**（DNS 挂）→ 加 `-G 3003` 重试 |
| root ✓ / appuid ✗ / bareip ✗ | 路由 / 网络注册问题（另一类）→ 查 `ip rule`、`dumpsys connectivity` |
| `Groups:` 为空 | 确诊附属组缺失 |

处置：

```sh
su -g 10541 -G 3003 10541 -c "$PREFIX/bin/bash $HOME/dsh-go.sh restart"
```

> ⚠️ **用户位置参数必须在 `-c` 之前**，否则实际以 root 跑。

**不要做的事**：加 `ip rule`、`am start` 唤醒 App、关 Data Saver —— 这些对本坑**无效**。
（`ip rule` 加对了路由也照样不通，因为丢包在 cgroup-BPF，早于 netfilter 与路由。）

---

## B. 预设挂载

**症状**：DSH 启动会话时报 `preset "mobile-use" failed to mount`，
或者某轮运行直接失败、整个工作区的会话都恢复不了。

**定性**（用 DSH 官方发现器，判据与 DSH 一致）：

```bash
node ~/tools/check-preset-mount.mjs       # 或 termux/tools/check-preset-mount.mjs
```

输出里 `状态 = BROKEN >> row "xxx" names a plugin that cannot be resolved: yyy` 就是根因。

**处置**：把那个失效的插件名改成**当前 DSH 版本里的正确名字**。

> ⚠️ 这类名字**随 DSH 版本变**，不是「新名覆盖旧名」的单向关系。已确认的一例：
>
> | dsh 版本 | workflow 插件的包名 |
> |---|---|
> | ≤ `0.1.5-rc.3` | `@deepseek-ai/dsh-workflow-worker-thread` |
> | ≥ `0.1.6-alpha.1` | `@deepseek-ai/dsh-workflow-ptc` |
>
> 所以**先确认你的 dsh 版本再改**。改错方向等于把一个能挂的预设改成挂不了的。

```bash
# 先确认版本
node -p "require('@deepseek-ai/dsh/package.json').version"

# 若 <= 0.1.5-rc.3：
sed -i "s|@deepseek-ai/dsh-workflow-ptc|@deepseek-ai/dsh-workflow-worker-thread|g" \
  ~/.dsh/.agent-presets/mobile-use/agent.cordis.yml

# 若 >= 0.1.6-alpha.1：应当保持 -ptc（上游 HEAD 原样），**不要**执行上面那条 sed
```

改完**必须再跑一次** `check-preset-mount.mjs` 复校，看到 `OK（可挂载）` 再开 DSH。
（**不要只看文件在位** —— 装一份加载不了的预设会让整个工作区无法恢复。）

---

## C. flock

**症状**：每轮运行立刻失败 `flock is not supported on android-arm64`。

**定性**：
```bash
node -e 'console.log(process.platform)'    # android  ⟹ 就是这个
grep -c "platform === 'android'" \
  $PREFIX/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/node-addon-system/lib/flock.js
# 0 ⟹ 补丁没打上
```

**处置**：`bash install.sh --step 20`，然后用 `node termux/tools/verify-flock.mjs` 复验
（期望：首次成功 / 二次 `EAGAIN` / 释放后可重取）。

---

## D. npm 自身坏掉

**症状**：`npm: /usr/bin/env: bad interpreter: No such file or directory`

**处置**：`bash install.sh --step 15`。
**每次 `npm install -g <pkg>` 之后都要重跑**。

---

## E. 命令找不到被报成 Permission denied

**定性**：
```sh
sh -c 'a-command-that-does-not-exist-xyz'      # 也报 Permission denied ⟹ 是"找不到"
command -v <那个命令>
```

**处置**：把它暴露进 `$PREFIX/bin`。详见 [`pitfalls.md` 坑 2](pitfalls.md#坑-2android-的-dash-把命令找不到报成-permission-denied)。

---

## F. `EADDRINUSE`

**根因**：旧 dsh 实例没被杀掉。常见于**新旧实例属于不同 uid** —— 例如之前用 root 起过，
现在用 `su 10541` 起，就杀不掉。

**处置**：
```bash
su -c 'pkill -f "bin/dsh web"; sleep 2; pkill -9 -f "bin/dsh web"'
su -g 10541 -G 3003 10541 -c "$PREFIX/bin/bash $HOME/dsh-go.sh restart"
```
或直接用 `bash ~/dsh-root-restart.sh restart`（已封装：root 侧先清残留再带组启动）。

---

## G. 3080 打不开

```bash
# 1) 进程在不在
pgrep -af "bin/dsh web"
# 2) 本机端口
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3080/     # 401 ⟹ 正常（需 cookie/token）
# 3) 若是从电脑侧通过 adb 访问 —— forward 会在 USB 重连/重启后丢失
adb forward --list
adb forward tcp:3080 tcp:3080
```

- `401` = **正常**，只是没带 cookie。用 `cat ~/dsh-url.txt` 里那条带 token 的地址访问一次即可。
- `000` = 没在监听 ⟹ 回 [F](#f-eaddrinuse) 或直接 `bash ~/dsh-go.sh restart`。

---

## H. 副屏没了

**症状**：3070 网关无响应，或 DSH 报 `socket hang up`。

```bash
curl -s http://127.0.0.1:3070/api/status
# 期望: {"status":"running","display_id":N,...,"mode":"background"}

sh /data/adb/modules/agent_mobile_use/system/bin/vd start
```

> **虚拟副屏是运行态对象，重启即丢。** 模块自带的 `service.sh` 只拉起 `vd_server`，
> **不会重建副屏** —— 这正是开机自启脚本里必须跑一次 `vd start` 的原因。
> 详见 [`pitfalls.md` 坑 5](pitfalls.md#坑-5别同步调用结尾是-exec-常驻进程-的脚本)。

---

## I. adb 装 APK 被拦

```bash
adb shell settings put global verifier_verify_adb_installs 0
adb shell settings put global package_verifier_enable 0
```

---

## J. 开机自启没生效

```bash
bash ~/dsh-go.sh status         # 看「开机自启」段
cat ~/dsh-autostart.log         # Termux 侧副本
su -c 'cat /data/local/tmp/dsh-autostart.log'    # root 侧权威日志
```

日志里第一行的 `uptime=Ns` 是关键判据：

| `uptime` | 含义 |
|---|---|
| **≤ 120s** | ✅ **真·开机自启**生效（脚本在开机后 N 秒起跑） |
| 远大于此 | 只是有人手动跑过，**不是开机触发的** |

常见问题：

- **日志卡在 `--- vd start ---` 之后没有下文** → 同步调用了 `run_daemon.sh`（见坑 5），改成
  `vd start` 或后台化
- **日志里 `dsh-go rc=` 非 0** → 看紧跟其后的输出，多半是 [A](#a-出网--dns) 或 [F](#f-eaddrinuse)
- **完全没有日志** → `/data/adb/service.d/dsh-autostart.sh` 不在位，或该脚本没有可执行位
  ```bash
  su -c 'ls -la /data/adb/service.d/'
  ```
- **Termux 侧读不到 `/data/adb`** —— 这是正常的（权限如此），不要据此判定"脚本缺失"；
  用「日志时间 vs 本次开机时间」判定（`status` 已这么做）。
