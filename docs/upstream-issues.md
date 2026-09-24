# 上游问题与补丁对照表

> 本仓库的三个补丁都是**临时绕过**，不是最终方案。上游修好后，对应步骤应当删掉。
>
> 调研时间：2026-09-24。三个上游仓库均为 **MIT**、且当时都在活跃维护中。
> GitHub 直连不通的环境下，可用 `curl -x http://127.0.0.1:7897 https://api.github.com/...`（本机实测）。

---

## 总览

| # | 上游仓库 | 问题 | 本仓库补丁 | 上游状态 |
|---|---|---|---|---|
| 1 | `AcidGr/dsh-preset-mobile-use` | 预设的插件名与它**自己声明的兼容 dsh 版本**不匹配 | `patches/0002-…`（**仅 dsh ≤ 0.1.5-rc.3 需要**） | 🟡 **上游 HEAD 本身没错**；可报的是兼容性声明不实 |
| 2 | `AcidGr/agent-mobile-use` | LSPosed 作用域写入用旧表结构，报错被吞 | `patches/0003-…` | 🔴 未修 |
| 3 | `deepseek-ai/deepseek-harness` | `node-addon-system` 无 Android 支持 | `patches/0001-…` | 🟡 未修（属平台支持策略，建议先开 Issue） |

---

## 1. `AcidGr/dsh-preset-mobile-use` — 插件名与声明的兼容版本不匹配

- 仓库：https://github.com/AcidGr/dsh-preset-mobile-use
- 协议：MIT｜调研时 ★39｜最后提交 2026-09-23｜**open issues = 0 / PR = 0**

### ⚠️ 先纠正一个曾经的误判

初版调研（2026-09-24 上午）写的是「`ptc` 已改名，上游没跟上，要提 PR 改回 `worker-thread`」。
**这个方向是反的，已撤销。** 完整证据链见
`D:\OnePlus\mobile-use\pr\FINDINGS-2026-09-24-version-floor.md`，核心事实：

| dsh 版本线 | workflow 插件的**真实**包名 |
|---|---|
| ≤ `0.1.5-rc.3` | `@deepseek-ai/dsh-workflow-worker-thread` |
| ≥ `0.1.6-alpha.1` | `@deepseek-ai/dsh-workflow-ptc` |

改名方向是 **`worker-thread` → `ptc`**，发生在 **0.1.6-alpha.1 边界**。
三方独立证据：

1. **npm 版本线连续**：`worker-thread` 20 个版本止于 `0.1.5-rc.3`；
   `ptc` 从 `0.1.6-alpha.1` 起，两条线**无重叠版本**。
2. **官方自带预设换了名字**：取 `@deepseek-ai/dsh-agent-presets` 官方 tarball，
   自带 `ptc` 预设在 `0.1.5-rc.3` 用 `worker-thread`、在 `0.1.6-alpha.1` 与 `0.1.6-alpha.2` 用 `ptc`。
3. **上游仓库从没用过 `worker-thread`**：release `v1.0.0 / v1.2.0 / v1.3.0 / v1.3.5` 以及 `main` HEAD
   的 `agent.cordis.yml` **全部**写 `ptc`；`cordis.patch.yml:252`（`package.json` 的
   `files` 与 `dsh.bundle.patch` 所指、即实际发布的 bundle patch）同样写 `ptc`。

⟹ **上游 HEAD 写 `ptc` 是正确的**（HEAD 提交就是 "upgrade to standard DSH 0.1.7 bundle specification"）。
本仓库的 `patches/0002-…` 之所以存在，是因为**我们的目标设备跑 dsh 0.1.5-rc.3** —— 那是**设备侧版本适配**，
不是上游 bug。**在 dsh ≥ 0.1.6 上打这个补丁会把预设改坏。**

### 真正可报的问题：`package.json` 的兼容性声明不实

`package.json` → `dsh.compatibility.dshReleases` 声明：

```json
"0.1.2-alpha.2": "compatible", "0.1.2-alpha.3": "compatible", "0.1.2-alpha.4": "compatible",
"0.1.2-alpha.5": "compatible", "0.1.2-rc.1": "compatible", "0.1.3-alpha.1": "compatible",
"0.1.3-alpha.2": "compatible", "0.1.5-alpha.1": "compatible", "0.1.5-alpha.2": "compatible",
"0.1.5-rc.1": "compatible", "0.1.5-rc.2": "compatible", "0.1.5-rc.3": "compatible",
"0.1.6-alpha.1": "compatible", ...
```

**但这 12 个 < 0.1.6 的版本上，预设引用的 `@deepseek-ai/dsh-workflow-ptc` 根本不存在。**
在这些版本上安装本预设，DSH 官方发现器会报：

```
row "workflow-ptc" names a plugin that cannot be resolved: @deepseek-ai/dsh-workflow-ptc
```

后果按该仓库 README 自己的说明：**该工作区里所有会话都无法恢复**。

### 可选修法

| 方案 | 做法 | 取舍 |
|---|---|---|
| **A（最简，推荐）** | `dshReleases` 里 < 0.1.6 的条目改成 `"incompatible"`，或只保留 `>= 0.1.6` | 一行 JSON，诚实；放弃旧版本用户 |
| **B** | 运行时按 dsh 版本挑名字（`!!js` 表达式，两个名字试解析） | 保留旧版本兼容；但两个引擎隔离模型不同（线程 vs 进程），**「可互换」这个假设需要先验证** |
| **C** | 只在 README 写明「要求 dsh ≥ 0.1.6」 | 最小改动；但 `package.json` 的声明仍是错的 |

> `ptc` 引擎 README 提到「The engine rejects non-TypeScript PTC providers when it loads」、
> 「Python PTC compositions must disable the `workflow-ptc`, `tool-workflow` and any enabled
> `tool-ralph` rows」—— 说明 `ptc` 对运行时有额外要求，**方案 B 不能想当然**。

### 本仓库的处置

`patches/0002-…` **保留但限定条件**：仅当目标设备 dsh ≤ 0.1.5-rc.3 时才应用。
`patches/apply-all.sh` 会自动探测 dsh 版本并在 ≥ 0.1.6 时跳过它。
**升级 dsh 到 ≥ 0.1.6 后，这份补丁必须撤销**（否则反过来挂掉）。

### 为什么上游自己的 gate 没拦住它（仍然值得单独提）

`install.sh` 的守门**只覆盖了一个文件**：

```bash
if ! node "$DIR/check-preset.mjs" "$SRC/mobile_plugin.js"; then   # ← 只传了 js 插件
	echo "refusing to install: the plugin does not mount" >&2; exit 1
fi
cp -f "$SRC/agent.cordis.yml" "$SRC/mobile_plugin.js" "$SRC/preset.yml" "$DST/"   # ← yml 零校验直接拷
```

而 `check-preset.mjs` 只做：`import` 那个 js → 用 stand-in ctx 跑一遍 `apply()` →
断言 `ctx.tools.register` 被调用 → 打印 `OK: N tools mount cleanly`。
**它从头到尾没有解析 `agent.cordis.yml`。**

⟹ composition 里任何失效的插件名都是**不可守门区**。

**建议的 PR**：把 composition 行的可解析性纳入 gate。关键是**用「当前装着的这个 dsh」去解析**，
而不是拿固定的名字表比对 —— 推荐直接用 DSH 官方的 `@deepseek-ai/dsh-agent-presets` 的
`discoverPresets()`（返回值的 `broken` 字段就是 DSH 自己的判定口径）。
本仓库的 `termux/tools/check-preset-mount.mjs` 可直接作为实现参考。
（这条思路对「版本下限」类问题同样有效，是原 PR-2 三个选项里唯一正确的一个。）

---

## 2. `AcidGr/agent-mobile-use` — LSPosed 作用域写入用了旧表结构

- 仓库：https://github.com/AcidGr/agent-mobile-use
- 协议：MIT｜调研时 ★62｜最后提交 2026-09-23
- 模块作者署名（`customize.sh` 内）：**酸小明**

### 问题

`customize.sh` 里这段（原版）：

```sh
"$SQLITE_BIN" "$LSP_DB" "INSERT OR REPLACE INTO modules (module_pkg_name, apk_path) VALUES ('com.agent.mobileuse', '$APK_PATH');" 2>/dev/null
"$SQLITE_BIN" "$LSP_DB" "INSERT OR REPLACE INTO modules_state (module_pkg_name, user_id, enabled) VALUES ('com.agent.mobileuse', 0, 1);" 2>/dev/null
"$SQLITE_BIN" "$LSP_DB" "INSERT OR REPLACE INTO scope (module_pkg_name, app_pkg_name, user_id) VALUES ('com.agent.mobileuse', 'android', 0);" 2>/dev/null
"$SQLITE_BIN" "$LSP_DB" "INSERT OR REPLACE INTO scope (module_pkg_name, app_pkg_name, user_id) VALUES ('com.agent.mobileuse', 'system', 0);" 2>/dev/null
ui_print "- LSPosed 作用域配置完成: $APK_PATH"
```

对照真实 schema（`/data/adb/lspd/config/modules_config.db`，Vector 2.2 / API 102 实测）：

| 原版写法 | 真实情况 |
|---|---|
| `scope(module_pkg_name, …)` | `scope(mid, app_pkg_name, user_id)` —— **没有 `module_pkg_name` 列** |
| `modules_state(…)` | **该表不存在**；启用位在 `modules.enabled` |
| `modules(module_pkg_name, apk_path)` | 这条列名恰好一致 → **能成** |

### 后果

`2>/dev/null` 把错误吞掉了，`ui_print` 照样印"作用域配置完成"。实际结果是：
**`modules` 表有行、`scope` 表为空** ⟹ hook 一次都不会跑
（跨屏焦点隔离 / 免软键盘弹窗失效），但安装日志显示成功。

实测证据（`scope` 表只有 `system`、缺 `android`）：

```
mid  module_pkg_name      app_pkg_name  user_id
190  com.agent.mobileuse  system        0        ← 只有这一行，android 缺失
```

### 修复

见 `patches/0003-agent-mobile-use-lsposed-scope.patch`。要点：

1. `modules` 表：列名保持不变（本来是对的）
2. 启用改到 `modules.enabled`（不是不存在的 `modules_state`）
3. **作用域要按 `mid` 写** —— 先 `SELECT mid FROM modules WHERE module_pkg_name='…'` 查回来，
   再 `INSERT OR IGNORE INTO scope (mid, app_pkg_name, user_id)`
4. **改完真校验**：`SELECT count(*) FROM scope WHERE mid=?`，不足就报警而不是假装成功
5. 收尾跑一次 `PRAGMA integrity_check`

> ⚠️ 作用域含 `android`（system_server 级目标），**需重启一次才生效**。

---

## 3. `deepseek-ai/deepseek-harness` — `node-addon-system` 没有 Android 支持

- 仓库：https://github.com/deepseek-ai/deepseek-harness（★234k，MIT，**有 `CONTRIBUTING.md`**）
- 包路径：**`native/system/packages/`** —— 其下只有
  `darwin-arm64 | darwin-x64 | linux-arm64 | linux-x64 | entry`
  ⟹ **官方确实没有 android**

### 问题

`@deepseek-ai/node-addon-system/lib/flock.js`：

```js
if (platform !== 'linux' && platform !== 'darwin') {
    throw Object.assign(new Error(`flock is not supported on ${platform}-${arch}`), {
        code: 'ERR_FLOCK_UNSUPPORTED_PLATFORM', syscall: 'flock',
    });
}
```

Termux 里 Node 是 Android 目标构建，`process.platform === 'android'` ⟹ 每轮会话直接挂在
`flock is not supported on android-arm64`。

调用方是 `dsh-session-persistence-jsonl` 的 `SessionWriteLease`（给 `session.lock` 加写锁）。

**加码难点**：即便放开白名单也走不通 —— 它接着会按 glibc/musl 二选一（
`report.header.glibcVersionRuntime ? 'glibc' : 'musl'`），而 Android 走 Bionic，
该字段是 `undefined`，于是会去 `require` 一个不存在的 `musl/system.node`。

### 本仓库的绕过

用 DSH 已内置的 **koffi**（带 `@koromix/koffi-android-arm64` 预编译产物）直接 FFI 调
Bionic 的 `flock(2)`，语义与原实现一致（成功 `0`；失败回 `koffi.errno()` 正值，
恰好对上调用方的 `getSystemErrorName(-errno)` 与 `EAGAIN`/`EWOULDBLOCK` 判定）。

```js
if (platform === 'android') {
    const require = createRequire(import.meta.url);
    const koffi = require('koffi');
    const libc  = koffi.load('libc.so');
    const flock = libc.func('int flock(int fd, int op)');
    const LOCK_EX = 2, LOCK_NB = 4;
    binding = { tryLock(fd, report) { report(flock(fd, LOCK_EX | LOCK_NB) === 0 ? 0 : koffi.errno()); } };
    return binding;
}
```

完整改动见 `patches/0001-node-addon-system-android-flock.patch`（基于 0.1.5-rc.3 shipped 版本，
原文件 2263 B，改后 4605 B）。语义验证见 `termux/tools/verify-flock.mjs`。

### 为什么建议先开 Issue 而不是直接 PR

这属于「**要不要在官方包里支持 Android/Termux**」的平台支持策略问题，不是纯 bug。
建议的 Issue 内容：

- 现象 + 原文报错
- `native/system/packages/` 下只有四个平台目录这一事实
- Bionic 导致 `glibcVersionRuntime === undefined` 的次生障碍
- 一个可行实现（koffi 调 `flock(2)`；或补一个 `android-arm64` 预编译包）
- 问一句"收不收"

---

## 如何复现本仓库的调研

```sh
P=http://127.0.0.1:7897        # 本机代理；直连 GitHub 不通

# 仓库元信息
curl -s -x $P https://api.github.com/repos/AcidGr/dsh-preset-mobile-use

# 现有 issue / PR
curl -s -x $P "https://api.github.com/repos/AcidGr/dsh-preset-mobile-use/issues?state=all"

# 取文件（raw 偶发 000 时用 contents API + base64 更稳）
curl -s -x $P https://api.github.com/repos/AcidGr/dsh-preset-mobile-use/contents/preset/mobile-use/agent.cordis.yml \
  | python -c "import json,sys,base64;print(base64.b64decode(json.load(sys.stdin)['content']).decode())"
```
