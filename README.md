# DSH Android Mobile-Use — fully automated on-device deployment

> Turn a **rooted Android phone** into a self-contained host for an AI agent that can operate
> Android by itself: DSH (DeepSeek Harness) runs inside Termux, and the `mobile-use` preset
> lets the agent use a **background virtual display** for screenshots, UI-tree parsing,
> taps, swipes, silent text injection and root shell — **without disturbing the physical
> main screen at all**.

English | [简体中文](README.zh.md)

---

## What this is

An **integration layer**: it wires three MIT upstream projects together into something that
actually runs on a real device, and ships the pitfalls, patches and ops scripts collected
along the way.

```
┌──────────────────────────────────────────────────────────────────────┐
│  Phone (Android, rooted)                                             │
│                                                                      │
│   ┌───────────────────────────┐        ┌──────────────────────────┐  │
│   │  Physical display (0)     │        │ Virtual display (2)      │  │
│   │  you keep using it        │        │ AgentVirtualDisplay      │  │
│   └───────────────────────────┘        │ 1440x3168 @560dpi        │  │
│                                        └────────────▲─────────────┘  │
│                                                     │ render/input   │
│   ┌─────────────────────────────────────────────┐   │                │
│   │ (1) KSU module  agent-mobile-use            │───┘                │
│   │     creates the display · vd CLI · LSPosed  │                    │
│   │     vd_server REST gateway  127.0.0.1:3070 ◄┼──────────┐        │
│   └─────────────────────────────────────────────┘          │        │
│                                                            │ HTTP   │
│   ┌────────────────────────────────────────────────────┐   │        │
│   │ Termux  ← this repo handles this layer              │   │        │
│   │   (2) DSH  @deepseek-ai/dsh  0.1.5-rc.3            │   │        │
│   │   (3) mobile-use preset ── mobile_* tools ─────────┼───┘        │
│   │       Web UI  http://127.0.0.1:3080                │            │
│   └────────────────────────────────────────────────────┘            │
└──────────────────────────────────────────────────────────────────────┘
        (1) AcidGr/agent-mobile-use        (MIT)
        (2) deepseek-ai/deepseek-harness   (MIT)
        (3) AcidGr/dsh-preset-mobile-use   (MIT)
```

## Requirements

| Item | Requirement | Verified on |
|---|---|---|
| Device | any **rooted arm64** Android phone | OnePlus 13 (PJZ110, China) |
| OS | Android 15 / 16 | crDroid 12.12 (Android 16) |
| Root | KernelSU / SukiSU / APatch with KSU-module + `service.d` support | SukiSU-Ultra v4.2.0 (LKM) |
| Xposed | Vector (formerly LSPosed), API ≥ 102 | Vector 2.2 / API 102 |
| Termux | the **debug-signed APK from GitHub Releases** (`run-as` needs it) | v0.118.3 |
| Node | ≥ 22 (DSH depends on built-in `node:sqlite`) | 26.4.0 |

> ⚠️ **Nothing here flashes anything.** It installs APKs, drops files, registers an LSPosed
> scope and runs Node inside Termux — **no low-level partition is written**, so it is
> unrelated to ARB / anti-rollback / bricking risk.

---

## Quick start

```bash
# 1) Set up the foundation first (out of scope for this repo — follow the upstream README):
#    - flash the agent-mobile-use KSU module
#    - install Vector, enable agent_hook, tick scope android + system, reboot once
#    - make sure the gateway answers:   curl -s http://127.0.0.1:3070/api/status

# 2) Get this repo onto the phone
cd /path/to/dsh-android-mobile-use/termux

# 3) One-shot deploy (idempotent, safe to re-run)
bash install.sh

# 4) Bring it up
bash ~/dsh-go.sh start
bash ~/dsh-go.sh status      # first section is the supplementary-groups + connectivity check
```

Then open the `http://127.0.0.1:3080/?token=…` URL it prints, **switch the preset picker
(top right) to `mobile-use`**, start a session, and say:

> "take a screenshot"

### Per-step execution

```bash
bash install.sh --list        # list steps
bash install.sh --step 20     # run a single, idempotent step
```

| Step | Does |
|---|---|
| `10` | switch APT to a CN mirror → install node/python/clang/cmake/… → install DSH |
| `15` | fix npm/npx shebangs (Android has no `/usr/bin/env`) |
| `20` | apply the Android `flock` patch to `node-addon-system` |
| `25` | install the `mobile-use` preset into `~/.dsh/.agent-presets/mobile-use/` |
| `30` | align the preset's workflow plugin name **with your dsh version** + re-verify mountability with DSH's own discovery API |
| `40` | deploy runtime scripts and boot autostart |

---

## Layout

```
.
├─ README.md / README.zh.md
├─ CREDITS.md                    ← upstream attribution (MIT requires keeping it)
├─ LICENSE
├─ termux/                       ← on-device (runs inside Termux)
│  ├─ install.sh
│  ├─ 10-dsh-termux-install-tuna.sh
│  ├─ 15-fix-npm-shebang.sh
│  ├─ 25-install-preset.sh
│  ├─ dsh-go.sh                  ← start/restart/stop/status/url
│  ├─ dsh-root-restart.sh        ← root-side restart with supplementary groups
│  ├─ dsh-autostart.sh           ← boot autostart (deploy to /data/adb/service.d/)
│  └─ tools/
│     ├─ check-preset-mount.mjs
│     ├─ verify-flock.mjs
│     └─ prep-nodegyp.sh
├─ patches/                      ← three upstream patches (all `git apply`-able)
│  ├─ 0001-node-addon-system-android-flock.patch
│  ├─ 0002-preset-workflow-plugin-name-dsh-le-0.1.5.patch   ← ⚠️ only for dsh <= 0.1.5-rc.3
│  ├─ 0003-agent-mobile-use-lsposed-scope.patch
│  ├─ customize.sh.fixed         ← full result of patch 0003, for a copy-over instead
│  └─ apply-all.sh               ← applies all three (idempotent, detects "already applied")
└─ docs/
   ├─ pitfalls.md
   ├─ troubleshooting.md
   └─ upstream-issues.md
```

---

## Day-to-day

```bash
bash ~/dsh-go.sh start|restart|stop|status|url
```

`status` prints: supplementary-group check → connectivity check → dsh processes → port 3080
→ gateway 3070 → **whether boot autostart actually fired this boot**.

### About the login token (the part that saves you time)

- The token **changes on every start**, but **you never need to copy a new URL**.
- The cookie signing key is persisted in `~/.dsh/.credentials.yaml`, and the cookie is bound
  to **host:port only** (no token in it), valid for 30 days.
- ⟹ Visit the tokenised URL **once**, then bookmark the bare `http://127.0.0.1:3080/`.
  It keeps working across dsh restarts.

### Boot autostart

`/data/adb/service.d/dsh-autostart.sh` is installed, so a reboot needs zero interaction:

```
wait for sys.boot_completed → vd start (recreate the virtual display)
  → battery-optimisation allowlist + standby bucket active + wake the Termux app (auxiliary)
  → connectivity self-test *with supplementary groups* (hits api.deepseek.com, 6 retries)
  → su -g 10541 -G … 10541 -c 'bash ~/dsh-go.sh start'
```

To confirm it really ran after a reboot:

```bash
bash ~/dsh-go.sh status      # the "boot autostart" section shows the uptime it started at
cat ~/dsh-autostart.log
```

---

## The five pitfalls you will hit

Full write-up: **[`docs/pitfalls.md`](docs/pitfalls.md)**.

1. **`su <uid>` sets no supplementary groups ⟹ DNS dies.** Without `inet(3003)` the process
   cannot reach `/dev/socket/dnsproxyd`, so **raw IPs work but every hostname returns
   ENOTFOUND**, surfacing as `connection error`. The #1 pitfall here.
2. **Android's `dash` reports "command not found" as `Permission denied`.**
3. **`npm install -g npm@<ver>` breaks npm itself** — upstream `npm-cli.js` starts with
   `#!/usr/bin/env node`, which does not exist on Android.
4. **`process.platform === 'android'`** — any package allow-listing `linux`/`darwin` fails
   (here: `flock`).
5. **Never call a script that ends in `exec <daemon>` synchronously** — it hangs your
   boot script forever.

Also: **`pkg update && pkg upgrade` resets Termux's `sources.list` back to the official
mirror**, which is effectively unreachable from mainland China.

---

## Known issues & upstream patch status

See **[`docs/upstream-issues.md`](docs/upstream-issues.md)**.

| Upstream | Issue | Patch | Upstream status |
|---|---|---|---|
| `AcidGr/dsh-preset-mobile-use` | the preset's `workflow` plugin name does not match the dsh versions it **declares itself compatible with** (that package is `-worker-thread` on ≤0.1.5, `-ptc` from 0.1.6). **Upstream HEAD is correct**; the reportable issue is the inaccurate `package.json` compatibility list | `0002` (**only needed on dsh ≤ 0.1.5-rc.3**) | unfixed upstream, and **should not be sent as a PR** |
| `AcidGr/agent-mobile-use` | `customize.sh` writes the LSPosed scope with an outdated schema (`scope(module_pkg_name,…)` vs the real `mid` key), errors swallowed by `2>/dev/null` → hook silently inactive | `0003` | unfixed |
| `deepseek-ai/deepseek-harness` | `@deepseek-ai/node-addon-system` ships darwin/linux only → `flock is not supported on android-arm64` on Termux | `0001` (uses the bundled koffi to call Bionic `flock(2)`) | unfixed (platform-policy question, discuss first) |

**These patches are workarounds, not the endgame** — drop each step once upstream fixes it.

---

## Cloning / contributing on Windows

Every script here is an **LF** shell script — turn it into CRLF and you get
`syntax error: unexpected 'in'` / `unexpected token '{'`.

This repo ships a `.gitattributes` (`* text=auto eol=lf`), so **a fresh clone is LF regardless of
your `core.autocrlf` setting**. No extra setup needed:

```bash
git clone <this repo>
```

**Applying a patch is the one place `core.autocrlf` still bites.** On Windows it is frequently set to
`true` at the **system** level, which makes `git apply` rewrite the whole file to CRLF. Either pass
`-c` every time, or set it once locally:

```bash
git config --local core.autocrlf false        # once is enough
git apply patches/0001-node-addon-system-android-flock.patch
```

**Which shell?** Either works — but note one trap that has nothing to do with the shell:
`git.exe` is a **native Windows binary** and does **not** understand MSYS-style paths.
Measured: `git apply /d/.../x.patch` → `error: can't open patch`; `D:/...` → succeeds.
So in **both cmd and Git Bash**, hand `git apply` a `D:/...` path:

```bash
git apply "D:/path/to/patches/0001-node-addon-system-android-flock.patch"   # ✓
git apply  /d/path/to/patches/0001-...patch                                 # ✗ can't open patch
```

**Self-check:**

```bash
python tools/lint-repo.py                      # whole-repo LF + `sh -n`
git config --get core.autocrlf                 # expect false
git ls-files --eol README.md                   # expect i/lf  w/lf
```

---

## Credits

All three upstreams are MIT. **This repo bundles and redistributes none of their binaries**;
the installer fetches from official sources on demand. Full attribution and the exact list of
changes per upstream → **[`CREDITS.md`](CREDITS.md)**.

## Disclaimer

- This project only integrates and orchestrates; it provides no capability to bypass or defeat
  security mechanisms.
- Through the foundation module the agent effectively has **root** (including `mobile_shell`).
  Assess the data risk on your own device — and **never expose the 3070 gateway to your LAN**
  (both the patches and the deploy scripts assume loopback-only).
- Misuse on a real device can destroy data. **Back up first.**
