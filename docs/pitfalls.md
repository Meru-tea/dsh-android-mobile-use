# 五个真坑（按顺序读）

> 全部是 2026-09 在一加13（crDroid 12.12 / Android 16 / Termux v0.118.3 / Node 26.4.0 /
> dsh 0.1.5-rc.3）上实际踩到并定性的。每条都给了「症状 → 30 秒定性法 → 根因 → 处置」。
>
> **先读第 1 条。** 它最隐蔽，也最容易把人带到完全错误的方向。

---

## 坑 1（头号）`su <uid>` 不设附属组 ⟹ DNS 全挂

### 症状

- DSH Web UI 里发请求 → **`connection error`** / **`request timeout`**
- 或者在 Termux 里跑任何按域名的命令 → `Could not resolve host`
- 但**用 root 跑同一条命令完全正常**

### 30 秒定性法（分水岭在第 2 步）

```sh
U=https://api.deepseek.com/

# ① 比 root 与目标 uid
su -c      "curl -s -m 8 -o /dev/null -w 'root   HTTP=%{http_code} dns=%{time_namelookup}s conn=%{time_connect}s\n' $U"
su 10541 -c "curl -s -m 8 -o /dev/null -w 'appuid HTTP=%{http_code} dns=%{time_namelookup}s conn=%{time_connect}s\n' $U"

# ② ★关键★ 再让目标 uid 打一个【裸 IP】
su 10541 -c "curl -s -m 8 -o /dev/null -w 'bareip HTTP=%{http_code} conn=%{time_connect}s\n' http://223.5.5.5/"
```

- **裸 IP 通、域名不通** ⟹ **DNS 层问题，别再去查路由/防火墙/网络注册**（就是本条）
- 两者都不通 ⟹ 才是网络注册 / 路由问题（另一类，见文末）

### 根因

```sh
ls -la /dev/socket/dnsproxyd
# srw-rw---- 1 root inet    ← 只有 root 或 inet 组成员能连
```

Android 的域名解析走 netd 的 `dnsproxyd` socket。
而 **KernelSU / Magisk 的 `su <uid>` 只设 uid/gid，不设 supplementary groups** ⟹ 进程没有
`inet(3003)` 组 ⟹ **连不上 dnsproxyd ⟹ 所有域名解析失败**。
裸 IP 连接不需要这个组，所以"网络看着是好的"，极容易误判成服务端故障。

**铁证（同一台机、同一条命令、三连）**

```
A  su 10541                        -> HTTP=000 dns=0.000000s   /proc/self/status → Groups:（空）  ✗
B  su -g 10541 -G 3003 10541 -c …  -> HTTP=401 dns=0.001273s   Groups: 3003                      ✓
C  su 10541（复测）                 -> HTTP=000 dns=0.000000s   Groups:（空）                     ✗
```

### ⚠️ 两个"会骗人"的地方

1. **Android 的 `id`（toybox）会骗人** —— 附属组为空时它照样打印主组名
   （`groups=10541(u0_a541)`），看起来像"有组"。
   **唯一可靠判据是 `/proc/self/status` 的 `Groups:` 行**：
   ```sh
   su 10541 -c 'grep Groups /proc/self/status'
   # Groups: 后面为空 ⟹ 就是这个问题
   ```
2. **`su` 的用户位置参数必须在 `-c` 之前**，否则你以为在切用户，其实还是 root：
   ```
   su -g 10541 -G 3003 -c "…"        -> Uid: 0        ✗（10541 只是主组！）
   su -g 10541 -G 3003 10541 -c "…"  -> Uid: 10541 + Groups: 3003   ✓
   ```
   验证：`grep -E '^(Uid|Groups)' /proc/<pid>/status`

### 处置

以目标 App 的**完整附属组**启动。组集合直接抄 `run-as <pkg> id`（去掉每 App 独有的 `50xxx`）：

```sh
TG="3003 1004 1007 1011 1015 1028 1078 1079 3001 3002 3006 3009 3011 3012"
GARGS="-g 10541"
for g in $TG; do GARGS="$GARGS -G $g"; done
su $GARGS 10541 -c "$PREFIX/bin/bash $HOME/dsh-go.sh start"
```

> **最少只需要 `-G 3003`（inet）就能修 DNS。** 抄全是为了同时拿到存储/日志等权限，
> 行为与 App 自身一致。完整实现见 `termux/dsh-autostart.sh` 里的 `TG`/`GARGS`。

### 顺带的两个操作细节

- **root 侧起的实例要用 root 去杀**：`uid 10541` 杀不掉 `uid 0` 的残留，会出现 `EADDRINUSE`。
  自启/重启脚本里先 `pkill` 再起（见 `termux/dsh-root-restart.sh`）。
- `run-as <pkg>` 也能给出完整组，但它的 SELinux 域是 `runas_app`，**杀不掉 `ksu` 域里起的旧进程**，
  混着用会互相卡住 —— 同一条链上统一用一种方式。

### 曾经的错误结论（留档，别重犯）

一度把同类故障归因于「Android 只给被 AMS 启动过的 App 进程登记网络」，并据此去
`am start` 唤醒 App —— **实测（HOT/COLD 都试）完全无效**。真因是附属组/DNS。
**教训：只要"裸 IP 通、域名不通"，就别往网络注册/路由上查。**

---

## 坑 2　Android 的 `dash` 把"命令找不到"报成 `Permission denied`

### 症状

```
sh: 1: node-gyp: Permission denied
```
看着像文件权限 / noexec / SELinux，实则**只是 PATH 里没有这个命令**。

### 根因

Termux 的 `/bin/sh` → dash。它在 PATH 里逐目录探测时，一旦某个目录 `stat` 返回 **EACCES**
（Android 的 PATH 含 `/vendor/bin`、`/system_ext/bin` 等受限目录），dash 就取这个非 ENOENT
的错误上报，"找不到"于是显示成"Permission denied"。

### 30 秒辨识法

```sh
sh -c 'a-command-that-does-not-exist-xyz'
# 若也报 Permission denied ⟹ 这就是"找不到"
command -v node-gyp || echo "PATH 里确实没有"
```

### 处置

把需要的 bin 暴露进 `$PREFIX/bin`。例（npm 自带的 node-gyp）：

```sh
ln -sf "$PREFIX/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js" "$PREFIX/bin/node-gyp"
```

---

## 坑 3　`npm install -g npm@<ver>` 之后 npm 自己坏掉

### 症状

```
npm: /usr/bin/env: bad interpreter: No such file or directory
```

### 根因

Termux 的 `npm`/`npx` 是软链 → `../lib/node_modules/npm/bin/npm-cli.js`，首行
`#!/usr/bin/env node`。Termux 的包在安装时会把 shebang 补好，但
**`npm install -g npm@<ver>` 会用上游文件覆盖，shebang 变回 `#!/usr/bin/env node`**，
而 **Android 根本没有 `/usr/bin/env`**。

`termux-fix-shebang` **治不了** —— 它只把 `*/bin/*` 改写成 `$PREFIX/bin/*`，`env` 被原样保留。

### 处置

把 shebang 直接换成 node 绝对路径（**必须追 `realpath`，否则 `sed -i` 会把软链替换成普通文件**）：

```sh
fp=$(realpath "$f"); first=$(head -n1 "$fp")
case "$first" in '#!'*'node'*) sed -i "1s|^#!.*|#!$PREFIX/bin/node|" "$fp" ;; esac
```

**每次 `npm install -g <pkg>` 之后都要重跑一遍**（新装的全局包同样带坏 shebang）。
扫描范围：`$PREFIX/bin/*`（其 realpath 是 `*.js`）+ `$PREFIX/lib/node_modules/**/.bin/*`。
实现见 `termux/15-fix-npm-shebang.sh`。

---

## 坑 4　`process.platform === 'android'`

### 症状

应用启动即报 `xxx is not supported on android-arm64`，或走进某个平台分支直接 throw。
字符串里那个"功能名"看着像缺依赖，很容易往错方向查。

### 根因

Termux 里 Node 是 Android 目标构建，**`process.platform` 是 `'android'`，不是 `'linux'`**。
任何用 `platform !== 'linux' && platform !== 'darwin'` 做白名单的包（或按 platform 拼预编译
包名 `<pkg>-${platform}-${arch}` 的包）在 Termux 上**必然失败**。
再加一层：Node 走 **Bionic libc**，`process.report.getReport().header.glibcVersionRuntime`
是 `undefined`，所以按 glibc/musl 二选一的逻辑也会选错。

### 排查第一步

```sh
node -e 'console.log(process.platform, process.arch, process.report.getReport().header.glibcVersionRuntime)'
# 期望: android arm64 undefined
```

### 修法优先级

1. **先看项目里有没有 koffi**（很多 Node 大项目会带）。有的话**不要**去编译原生模块 ——
   用 koffi 直接 FFI 调 Bionic libc 更省事：
   ```js
   const koffi = require('koffi');
   const libc  = koffi.load('libc.so');        // Bionic 就叫 libc.so（不是 libc.so.6）
   const flock = libc.func('int flock(int fd, int op)');   // LOCK_EX=2, LOCK_NB=4
   // 成功返回 0；失败返回 -1，errno 用 koffi.errno() 取（正值）
   ```
   只改项目内那份（`node_modules/<pkg>/...`），**先备份原文件**。
   若该包是 ESM，用 `createRequire(import.meta.url)` 解析 `koffi`。
2. 没有 koffi 时，才考虑用 node-gyp + clang 自己编 N-API addon。
   （**编译前置三件套**见坑 4 附录）
3. 纯逻辑降级（stub 成立即成功）是下策 —— 先看上游有没有先例才敢这么干。

**验收要打到函数级**：直接 `import` 生产代码用的那个模块，跑「首次成功 / 二次被拒 /
释放后可重取」三段，不要只看"应用能启动了"。见 `termux/tools/verify-flock.mjs`。

### 附录：Termux 上编原生模块（node-pty 等）的前置三件套

1. 暴露 node-gyp（见坑 2）
2. **预热 Node 头文件，走国内镜像**（`nodejs.org` 常不通）
   ```sh
   export npm_config_disturl="https://npmmirror.com/mirrors/node"
   node-gyp install --verbose      # 成功标志: gyp info ok
   ```
3. 给 `~/.cache/node-gyp/<ver>/include/node/common.gypi` 的 `variables` 加
   `'android_ndk_path%': ''`（较新 node-gyp 在 Android 上会引用它）

实现见 `termux/tools/prep-nodegyp.sh`。

---

## 坑 5　别同步调用结尾是 `exec <常驻进程>` 的脚本

### 症状

开机自启脚本**永久卡死**在该行：它自己变成 `ps` 里的僵尸进程，
而被调用的守护进程**正常起来了** —— 于是表现为「守护进程在跑，但主服务完全没启动」。

### 根因

`agent-mobile-use` 的 `run_daemon.sh` 结尾是：

```sh
exec /system/bin/app_process /system/bin com.agent.DaemonMain "$WIDTH" "$HEIGHT" "$DPI"
```

`exec` 之后就是一个**前台常驻守护进程，永不返回**。同步调用会把调用者永久停在这一行。

### 30 秒辨识法

```sh
tail -5 <被调脚本>        # 看有没有 exec
```

### 处置

- 优先用模块**自带的幂等生命周期命令**（本例是 `vd start` —— 内部 `nohup run_daemon.sh &`
  并轮询 `/data/local/tmp/vd_status.json` 直到就绪，已在跑就直接返回），比自己拼 `nohup` 可靠。
- 也可以自己后台化：`nohup <脚本> >> log 2>&1 &` —— 但要自己处理"就绪判定"和"重复启动"。
- 顺带：卡死时 `kill -9` 掉父脚本**不会**带走守护进程 —— `exec` 出来的进程会 reparent 到
  PID 1 继续活着。

---

## 附加坑（Termux 源）

### `pkg update && pkg upgrade` 会把源重置回官方源

`pkg upgrade` 会顺带升级 `termux-tools`，而它的 postinst 会把
`$PREFIX/etc/apt/sources.list` **重置回官方源**。官方源新地址在国内实测**0 包完成**
（等几小时也不动），而很多"一键安装脚本"第一步就是 `yes | pkg update; yes | pkg upgrade`
—— 于是卡死且看起来像网络问题。

**稳妥做法**：

```sh
TUNA='deb https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main stable main'
SRC="$PREFIX/etc/apt/sources.list"
[ -f "$SRC" ] && cp -f "$SRC" "$SRC.bak"
printf '%s\n' "$TUNA" > "$SRC"
export DEBIAN_FRONTEND=noninteractive
apt-get update -o Dpkg::Use-Pty=0
apt-get install -y nodejs git python make clang binutils cmake ninja libffi ripgrep openssh which
printf '%s\n' "$TUNA" > "$SRC"     # termux-tools 若被顺带升级会重置，补写一次
```

- 只用 `apt-get update + install`，**不做 upgrade**
- 不要给 apt 传 `npm`：Termux 的 `npm` 由 `nodejs` 提供，写错包名会让整条命令返回码 100 全盘失败
- 实测速率：清华源 ~390 KB/s，142 MB 依赖约 3 分钟
- 卡住过要清锁：`rm -f $PREFIX/cache/apt/archives/lock*`，并 `ps -A | grep apt` 杀残留

## 附：写手机上的 `.sh` 务必保证 LF

在 Windows 上用 Python 文本模式写文件会把 `\n` 变成 `\r\n`，**直接把 shell 脚本写坏**
（`syntax error: unexpected 'in'` / `unexpected token '{'`）。
写文件用二进制模式（`open(p,'wb')`）或事后统一转换；改完先 `sh -n` / `bash -n` 校验。
