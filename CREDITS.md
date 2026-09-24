# CREDITS / 上游与署名

本项目是**集成层**（integration layer），本身不包含任何设备能力或 Agent 能力。
真正干活的是下面三个上游项目 —— 全部 **MIT**，本仓库对它们只做「打补丁 + 编排 + 记录踩坑」。

---

## 1. `AcidGr/agent-mobile-use` — 底座模块（KSU）

- 仓库：https://github.com/AcidGr/agent-mobile-use
- 协议：MIT
- 作用：提供**后台独立虚拟副屏**（`AgentVirtualDisplay`）、`vd` 命令行、
  `vd_server` REST 网关（默认 `http://127.0.0.1:3070`）、以及负责跨屏焦点隔离 /
  免软键盘弹窗的 LSPosed 补丁 `agent_hook.apk`
- 作者署名（模块 `customize.sh` 内）：**酸小明**
- 本仓库对其的改动：`patches/0003-agent-mobile-use-lsposed-scope.patch`
  （修 `customize.sh` 里写 LSPosed 作用域那段 SQL 用了旧表结构、报错被 `2>/dev/null` 吞掉的问题）

## 2. `AcidGr/dsh-preset-mobile-use` — DSH 预设（工具层）

- 仓库：https://github.com/AcidGr/dsh-preset-mobile-use
- 协议：MIT
- 作用：把 DSH 变成能操作 Android 的 Agent —— 注入 `mobile_status` / `mobile_screenshot` /
  `mobile_dump_ui` / `mobile_click` / `mobile_swipe` / `mobile_type` / `mobile_press_key` /
  `mobile_launch_app` / `mobile_shell` 等工具，全部经 HTTP 打到 3070 网关
- 本仓库对其的改动：`patches/0002-preset-workflow-plugin-name-dsh-le-0.1.5.patch`
  —— **版本适配，不是修上游 bug**：该 preset 的 `workflow` 插件名随 DSH 版本而变
  （≤ 0.1.5-rc.3 是 `@deepseek-ai/dsh-workflow-worker-thread`，≥ 0.1.6-alpha.1 是
  `@deepseek-ai/dsh-workflow-ptc`）。**上游 HEAD 的写法本来就是对的**，
  这个补丁只在目标设备跑 dsh ≤ 0.1.5-rc.3 时需要。详见 `docs/upstream-issues.md` 第 1 节。

## 3. `deepseek-ai/deepseek-harness` — DSH 本体

- 仓库：https://github.com/deepseek-ai/deepseek-harness
- 协议：MIT
- 作用：Agent 运行时。本项目用的是 npm 包 `@deepseek-ai/dsh`
- 本仓库对其的改动：`patches/0001-node-addon-system-android-flock.patch`
  （给 `@deepseek-ai/node-addon-system` 的 `flock.js` 补上 Android 分支）

## 4. `w1ngy` — Termux 一键安装脚本（原始版本）

- `termux/10-dsh-termux-install-tuna.sh` 是**第三方 Termux 安装脚本的改良版**，
  原脚本的仓库地址**尚未确认**（GitHub 上有 `cokelaoshi1/android-termux-dsh`、
  `Hariketsu/dsh-termux-install`、`MIOYULIN/install-dsh-termux` 三个候选）。
- 本仓库对其的改动（都在文件头部注释里写明了）：
  1. **删掉 `pkg update && pkg upgrade`** —— 它会升级 `termux-tools`，而后者会把
     `sources.list` 重置回官方源（国内实测 0 包完成）
  2. 改成 `apt-get update + install`，并在前后各写一次清华源
  3. 修掉 `npm` 被降到 11.9.0 后 `#!/usr/bin/env node` 在 Android 上失效的问题

> ⚠️ **如果你知道原脚本来出自哪个仓库，欢迎提 Issue 告诉我们** —— 确认后会把
> 改良部分整理成 PR 回那个上游，并把这里的副本换成"引用 + 补丁"的形式。

---

## 第三方运行期依赖（不随本仓库分发）

| 名称 | 用途 | 获取方式 |
|---|---|---|
| Termux | Android 上的终端环境 | GitHub Releases 的 debug 签名 APK（`run-as` 可用） |
| `@deepseek-ai/dsh` | DSH 本体 | `npm i -g @deepseek-ai/dsh` |
| `koffi` | 被 DSH 内置，用来 FFI 调 Bionic `flock(2)` | 随 dsh 一起来 |
| Vector（原 LSPosed） | 加载 `agent_hook.apk` | `JingMatrix/Vector` |
| KernelSU / SukiSU / APatch | root 与 KSU 模块加载 | 各自官方 Release |

**本仓库不打包、不重分发上述任何二进制。** 安装脚本按需从官方来源拉取。
