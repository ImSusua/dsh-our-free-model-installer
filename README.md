# dsh-our-free-model 桌面端安装器

一键把 [dsh-our-free-model](https://gh.liloususu.eu.cc/ebony-vinyl/dsh-our-free-model)（dsh 免费 LLM 车道插件：装上即用 DeepSeek V4.1 Flash、Kimi K3 等前沿模型，无需登录、注册或 API Key）安装进 **dsh 桌面端（DSHEAC AIO / DeepSeek Harness）** 或 dsh web 的 profile。

> 本仓库是纯第三方安装工具，与上游插件作者及 dsh 官方无关。版本自动跟随上游发布清单（当前 v1.4.6）。

## 它解决什么问题

桌面端在启动 web 服务前会执行一道 **profile 闸门**：目录树中出现任何非 dsh 自身生成的符号链接 / junction，应用将拒绝启动（`PROFILE_UPGRADE_REQUIRED`）。因此桌面端**不能**用 `dsh plugin add`（junction 方式）安装，只能放置真实目录并手工完成注册——本脚本把这套手工流程完全自动化。

## 快速开始

**双击 `一键安装.bat`**，或命令行运行：

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File install-our-free-model.ps1
```

安装完成后**重启 dsh / 桌面端一次**。模型选择器出现 **Our Free Model** 分组即成功。

验证（可选）：

```
dsh --profile <名称> --dump-config | grep our-free-model
```

应只出现一个 `id: our-free-model`。

## 脚本做了什么

严格按上游 README 的桌面端规范执行，**全程不创建任何符号链接 / junction**：

1. **下载并校验**：拉取发布清单 `feed/manifest.json`，逐文件下载全部 32 个发布文件，按清单做 SHA-256 + 字节大小双重校验；
2. **真实目录安装**：复制到 profile 对应的 `node_modules/dsh-our-free-model/`（优先 profile 内 node_modules，其次 pnpm workspace 根的 `profiles/node_modules`，都没有则在 profile 内新建）；旧版本自动备份为 `dsh-our-free-model.bak-<时间戳>`；
3. **注册 bundle**：编辑 profile 的 `package.json`——`dependencies` 写入精确版本、`dsh.profile.bundles` 末尾追加（原文件备份为 `package.json.bak-ofm`）；
4. **不改动** `cordis.patch.yml`：bundle 引用的包其 patch 层自动生效，两处同时注册会报 `duplicate loader entry id: our-free-model`（脚本检测到时直接中止并提示）；
5. **自检**：版本一致性、bundles 条目唯一、关键文件齐全（`index.js / client.js / adapter/ / src/ / locale/ …`）；对桌面 profile 额外预扫描闸门敏感链接。

## 参数

| 参数 | 说明 |
|---|---|
| `-DshHome <路径>` | 指定 DSH_HOME（默认依次尝试 `%DSH_HOME%`、`~/.dsh`、自动扫描常见位置） |
| `-Profile <名称>` | 指定 profile（默认依次尝试 `web-desktop`（AIO 壳）、`desktop`（Electron 壳）、`web`） |
| `-Version <版本>` | 指定插件版本（默认取发布清单最新版） |
| `-Uninstall` | 卸载 |
| `-NoPause` | 结束后不停留（供脚本调用） |

## 常见问题

**启动报 `PROFILE_UPGRADE_REQUIRED: offline dependency migration is not yet available`**

profile 目录树中存在非 `.dsh-module-fallback` 的符号链接 / junction（本脚本不会产生，多为此前用 `dsh plugin add` 或手工 junction 造成）。关闭桌面端，删除该 profile 的 `node_modules` 与 `pnpm-lock.yaml` 使其重建，再重跑本脚本。

**安装/启动报 `ERR_PNPM_VIRTUAL_STORE_DIR_MAX_LENGTH_DIFF`**

profile 的 node_modules 由旧版 pnpm 生成所致，与插件无关。关闭 dsh，删除该 profile 的 `node_modules` 与 `pnpm-lock.yaml`，重新安装。

**所有下载源都失败**

脚本按 `gh.liloususu.eu.cc` → `ghfast.top` → `cdn.jsdelivr.net` → `raw.githubusercontent.com` 顺序自动回退，单个源成功后本轮固定使用。全部失败多为网络拦截，检查代理后重试。

## 卸载

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File install-our-free-model.ps1 -Uninstall
```

移除插件目录、`dependencies` 与 `bundles` 条目。升级/重装时自动备份的旧版本目录会保留，确认新版本正常后可手动删除。插件数据目录 `DSH_HOME\our-free-model\` 为纯 JSON，如需彻底清理可手动删除。

## 许可

MIT。上游插件 [dsh-our-free-model](https://gh.liloususu.eu.cc/ebony-vinyl/dsh-our-free-model) 遵循其自身许可（MIT）。
