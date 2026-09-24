# DSH Android 手机助手 · 端侧全自动部署

> 在**已 root 的 Android 手机**上，把手机本身变成一个能自主操作 Android 的 AI Agent 宿主：
> DSH（DeepSeek Harness）跑在 Termux 里，`mobile-use` 预设让 Agent 经**后台虚拟副屏**
> 完成截屏、控件树解析、点击、滑动、静默输入、root shell —— 而**物理主屏完全不被打扰**。

[English](README.md) | 简体中文

---

## 这是什么

一个**集成层（integration layer）**：把三个 MIT 上游项目在真机上编排到能跑，附上
一路上踩到的坑、修复补丁、以及开机自启等运维脚本。

```
┌──────────────────────────────────────────────────────────────────────┐
│  手机（Android，已 root）                                             │
│                                                                      │
│   ┌───────────────────────────┐        ┌──────────────────────────┐  │
│   │  物理主屏 Display 0        │        │ 虚拟副屏 Display 2        │  │
│   │  （你正常用手机，不被打扰）│        │ AgentVirtualDisplay      │  │
│   └───────────────────────────┘        │ 1440x3168 @560dpi        │  │
│                                        └────────────▲─────────────┘  │
│                                                     │ 渲染 / 触控     │
│   ┌─────────────────────────────────────────────┐   │                │
│   │ ① KSU 底座模块  agent-mobile-use            │───┘                │
│   │    · 建副屏 · vd CLI · LSPosed 补丁(焦点隔离)│                    │
│   │    · vd_server REST 网关  127.0.0.1:3070 ◄──┼──────────┐        │
│   └─────────────────────────────────────────────┘          │        │
│                                                            │ HTTP   │
│   ┌────────────────────────────────────────────────────┐   │        │
│   │ Termux（本仓库负责这一层）                          │   │        │
│   │   ② DSH  @deepseek-ai/dsh   0.1.5-rc.3             │   │        │
│   │   ③ mobile-use 预设 ──── mobile_* 工具集 ──────────┼───┘        │
│   │        Web UI  http://127.0.0.1:3080               │            │
│   └────────────────────────────────────────────────────┘            │
└──────────────────────────────────────────────────────────────────────┘
        ①  AcidGr/agent-mobile-use        (MIT)
        ②  deepseek-ai/deepseek-harness   (MIT)
        ③  AcidGr/dsh-preset-mobile-use   (MIT)
```

## 硬件 / 系统要求

| 项目 | 要求 | 实测环境 |
|---|---|---|
| 机型 | 任意已 root 的 arm64 Android | 一加13 国行（PJZ110） |
| 系统 | Android 15 / 16 | crDroid 12.12（Android 16） |
| root | KernelSU / SukiSU / APatch（需支持 KSU 模块 + `service.d`） | SukiSU-Ultra v4.2.0（LKM） |
| Xposed | Vector（原 LSPosed），API ≥ 102 | Vector 2.2 / API 102 |
| Termux | **GitHub Release 的 debug 签名 APK**（`run-as` 需要它） | v0.118.3 |
| Node | ≥ 22（DSH 依赖内置 `node:sqlite`） | 26.4.0 |

> ⚠️ **本文档不涉及刷机**。它只装 APK、放文件、注册 LSPosed 作用域、在 Termux 里跑 Node ——
> **不写任何底层分区**，因此与 ARB / 熔断 / 变砖风险无关。

---

## 快速开始

```bash
# ① 先装好底座（不在本仓库范围内，请照上游 README 做）：
#    - 刷入 agent-mobile-use 的 KSU 模块
#    - 装 Vector，启用 agent_hook，作用域勾 android + system，重启一次
#    - 确认网关在跑：  curl -s http://127.0.0.1:3070/api/status

# ② 把本仓库放到手机上（或用 git clone / 直接 push）
cd /path/to/dsh-android-mobile-use/termux

# ③ 一键部署（幂等，可重复跑）
bash install.sh

# ④ 起来
bash ~/dsh-go.sh start
bash ~/dsh-go.sh status      # 第一段就是「附属组 + 出网」自检
```

装完打开终端里回显的 `http://127.0.0.1:3080/?token=…`，
**右上角把预设切到 `mobile-use`**，开一个会话，然后对它说：

> 「截个屏看看」

### 分步执行

```bash
bash install.sh --list        # 看步骤清单
bash install.sh --step 20     # 只跑某一步（幂等）
```

| 步骤 | 做什么 |
|---|---|
| `10` | 换清华源 → 装 node/python/clang/cmake/… → 装 DSH |
| `15` | 修 npm/npx 的坏 shebang（Android 没有 `/usr/bin/env`） |
| `20` | 给 `node-addon-system` 打 Android `flock` 补丁 |
| `25` | 安装 `mobile-use` 预设到 `~/.dsh/.agent-presets/mobile-use/` |
| `30` | **按 dsh 版本**校正预设的 workflow 插件名 + 用 DSH 官方发现器复校可挂载性 |
| `40` | 部署运行期脚本与开机自启 |

---

## 目录结构

```
.
├─ README.md / README.zh.md      ← 你在这里
├─ CREDITS.md                    ← 三个上游的署名与链接（重要，MIT 要求保留）
├─ LICENSE
├─ termux/                       ← 端侧（在手机 Termux 里跑）
│  ├─ install.sh                 ← 一键编排
│  ├─ 10-dsh-termux-install-tuna.sh
│  ├─ 15-fix-npm-shebang.sh
│  ├─ 25-install-preset.sh
│  ├─ dsh-go.sh                  ← 启停 / 状态 / 地址
│  ├─ dsh-root-restart.sh        ← root 侧带附属组重启
│  ├─ dsh-autostart.sh           ← 开机自启（部署到 /data/adb/service.d/）
│  └─ tools/
│     ├─ check-preset-mount.mjs  ← 用 DSH 官方发现器校验预设可挂载
│     ├─ verify-flock.mjs        ← flock 补丁的语义验证
│     └─ prep-nodegyp.sh         ← node-gyp 暴露 + 头文件预热
├─ patches/                      ← 三个上游补丁（均可 git apply）
│  ├─ 0001-node-addon-system-android-flock.patch
│  ├─ 0002-preset-workflow-plugin-name-dsh-le-0.1.5.patch   ← ⚠️ 仅 dsh ≤ 0.1.5-rc.3 需要
│  ├─ 0003-agent-mobile-use-lsposed-scope.patch
│  ├─ customize.sh.fixed         ← 补丁 0003 的成品全文，想「直接覆盖」可用它
│  └─ apply-all.sh               ← 三个补丁一次打完（幂等，会检测「已打过」）
└─ docs/
   ├─ pitfalls.md                ← 五个真坑（照顺序读）
   ├─ troubleshooting.md         ← 症状 → 定性 → 处置
   └─ upstream-issues.md         ← 上游 bug / PR 状态对照表
```

---

## 日常运维

```bash
bash ~/dsh-go.sh start|restart|stop|status|url
```

| 子命令 | 作用 |
|---|---|
| `start` / `restart` | 启动 dsh web，把带 token 地址与裸地址写进 `~/dsh-url.txt` |
| `stop` | 停止 |
| `status` | 附属组自检 + 出网自检 + 进程 + 3080 + 3070 网关 + **开机自启是否真触发** |
| `url` | 只打印地址 |

### 关于登录 token（省事的关键）

- token **每次启动都会换**，但**你不需要每次复制新地址**。
- cookie 的签名密钥持久化在 `~/.dsh/.credentials.yaml`，且 cookie **只绑定 host:port**（不含 token），有效期 30 天。
- ⟹ **带 token 访问一次后，把裸地址 `http://127.0.0.1:3080/` 加书签，以后点书签直接就进**，重启 dsh 也不影响。

### 开机自启

已装 `/data/adb/service.d/dsh-autostart.sh`，开机后零操作：

```
等 sys.boot_completed → vd start 重建虚拟副屏
  → 电池优化白名单 + 待机桶 active + 唤醒 Termux App（辅助）
  → 带附属组的出网自检（打 api.deepseek.com，重试 6 次）
  → su -g 10541 -G … 10541 -c 'bash ~/dsh-go.sh start'
```

重启后想确认它真的跑了：

```bash
bash ~/dsh-go.sh status      # 看「开机自启」段：会显示脚本在开机后多少秒起跑
cat ~/dsh-autostart.log      # 完整日志
```

---

## 五个真坑（必读）

完整版见 **[`docs/pitfalls.md`](docs/pitfalls.md)**，这里只列标题：

1. **`su <uid>` 不设附属组 ⟹ DNS 全挂** —— 缺 `inet(3003)` 就连不上 `/dev/socket/dnsproxyd`，
   表现为**裸 IP 能连、所有域名 ENOTFOUND**，上层报 `connection error`。**本机头号坑。**
2. **Android 的 `dash` 会把"命令找不到"报成 `Permission denied`** —— 排查 `node-gyp` 之类时极易被带偏。
3. **`npm install -g npm@<ver>` 后 npm 自己坏掉** —— 上游 `npm-cli.js` 的 `#!/usr/bin/env node` 在 Android 上不存在。
4. **`process.platform === 'android'`** —— 任何按 `linux/darwin` 白名单判断的包必然失败（本例：`flock`）。
5. **别同步调用结尾是 `exec <常驻进程>` 的脚本** —— 会让开机自启脚本永久卡死。

> 另外：**`pkg update && pkg upgrade` 会把 Termux 源重置回官方源**（国内实测 0 包完成）。

---

## 已知问题与上游补丁状态

见 **[`docs/upstream-issues.md`](docs/upstream-issues.md)**。摘要：

| 上游 | 问题 | 本仓库 | 上游状态 |
|---|---|---|---|
| `AcidGr/dsh-preset-mobile-use` | 预设的 `workflow` 插件名与它**自己声明的兼容 dsh 版本**不匹配（≤0.1.5 该包叫 `-worker-thread`，≥0.1.6 才叫 `-ptc`）。**上游 HEAD 本身没错**，可报的是 `package.json` 的兼容性声明不实 | `0002`（**仅 dsh ≤ 0.1.5-rc.3 需要**） | 上游未修，也**不该当 PR 提** |
| `AcidGr/agent-mobile-use` | `customize.sh` 用旧表结构写 LSPosed 作用域（`scope(module_pkg_name,…)` vs 实际主键 `mid`），报错被 `2>/dev/null` 吞掉 → 装完 hook 不生效却显示成功 | `0003` 补丁 | 未修 |
| `deepseek-ai/deepseek-harness` | `@deepseek-ai/node-addon-system` 只提供 darwin/linux 预编译包，Termux 上 `flock is not supported on android-arm64` | `0001` 补丁（用内置 koffi 调 Bionic `flock(2)`） | 未修（属平台支持策略，需先讨论） |

**本仓库的补丁是"临时绕过"，不是最终方案** —— 上游修好后应删掉对应步骤。

---

## 在 Windows 上克隆 / 贡献（重要）

本仓库的脚本全是 **LF** shell 脚本 —— 一旦被写成 CRLF 就会报
`syntax error: unexpected 'in'` / `unexpected token '{'`。

本仓库已经带 `.gitattributes`（`* text=auto eol=lf`），**克隆下来就是 LF，与你的
`core.autocrlf` 设置无关**。所以：

```bash
git clone <本仓库>            # 不需要任何额外设置
```

**但打补丁时必须注意**：`git apply` 会受 `core.autocrlf` 影响，而 Windows 上它常在
**系统级**被设成 `true`。要么每次加 `-c`，要么在仓库里设一次 local：

```bash
git config --local core.autocrlf false        # 一次即可
git apply patches/0001-node-addon-system-android-flock.patch
```

**自检**：

```bash
python tools/lint-repo.py                      # 全仓库 LF + sh -n 体检
git config --get core.autocrlf                 # 期望 false（若上面设过）
git ls-files --eol README.md                   # 期望 i/lf  w/lf
```

> **用哪个 shell？** 推荐 **Git Bash**（写路径、跑 `sh -n`、`python tools/lint-repo.py` 都顺手）。
>
> ⚠️ 但有一条与 shell 无关的坑：`git.exe` 是**原生 Windows 程序**，它**不认 MSYS 风格路径**。
> 实测 `git apply /d/.../x.patch` → `error: can't open patch`；写成 `D:/...` → 成功。
> 所以**无论 cmd 还是 Git Bash**，交给 `git apply` 的路径一律写 `D:/...`：
>
> ```bash
> git apply "D:/OnePlus/dsh-android-mobile-use/patches/0001-node-addon-system-android-flock.patch"   # ✓
> git apply  /d/OnePlus/dsh-android-mobile-use/patches/0001-...patch                                # ✗ can't open patch
> ```
>
> （cmd 里同样只认 `D:\...` 或 `D:/...`。反过来说：只要路径写成 `D:/...`，两个 shell 行为一致。）

## 上游与署名

三个上游全部 MIT。**本仓库不打包、不重分发任何上游二进制**，安装脚本按需从官方来源拉取。
完整的署名、链接、以及对每个上游的改动清单 → **[`CREDITS.md`](CREDITS.md)**。

## 免责声明

- 本项目只做**集成与编排**，本身不提供任何绕过、破解或规避安全机制的能力。
- Agent 通过底座模块获得的能力**等同于 root**（含 `mobile_shell`）。请自行评估设备上的数据风险，
  尤其是**不要把 3070 网关暴露到局域网**（本仓库的 `patches/0003` 与部署脚本都按"仅本机"假设设计）。
- 在真机上误操作可能造成数据损失。**先备份**。
