# kb-code-search-skill

软件知识库代码检索 Skill 的一键迁移包。面向 MadGraph 3.5.13 / Delphes 3.5.0 /
FastJet 3.3.4 的源码与手册检索，以 grep 为发现路径，不依赖 MCP 服务、向量库
或专用检索模型。

## 包内容

- `migrate.sh`：一键迁移脚本（clone 知识库仓库、下载/校验/解包源码归档、恢复索引快照、安装 skill）
- `manifest.json`：安装脚本读取的知识库修订、归档文件、下载地址和 SHA256 的唯一清单
- `skill/kb-code-search/`：skill 本体（`SKILL.md` + `references/repo-map.md` 检索地图）
- `MG5_aMC_v3.5.13.tar.gz`：MadGraph pinned 源码归档（随包携带，上游已不再提供该构建）
- `index-070f1ea.tar.gz`：Python 符号索引快照（约 5800 条记录）
- `pinned-revisions.json`：各仓库修订与归档 sha256 校验和

## 用法

```bash
./migrate.sh --dir <项目文件夹> --agent codex

# 例如：在当前项目目录配置 Codex
./migrate.sh --dir . --agent codex
```

目标文件夹是用户打开的项目根目录。脚本会创建统一布局：

```text
<项目>/repos/software-infrastructure-knowledge-base/
<项目>/.codex/skills/kb-code-search/      # --agent codex
```

知识库固定放在 `repos/software-infrastructure-knowledge-base/`，skill 固定使用这个
相对路径，因此不用再区分“知识库根目录”和“项目根目录”。`--agent` 支持
`auto|kimi|claude|codex|all`，默认是 `codex`；旧的
`./migrate.sh <目标文件夹> [--agent ...]` 写法仍然兼容。

脚本可以在已有项目目录中执行，不会覆盖目录里的其他文件。若源码或索引需要更新，
旧版本会移动为 `*.backup.<时间戳>`，不会默认删除；第二次运行在版本不变时会跳过
已完成的下载、解包和 skill 安装。

可选环境变量：`KB_GIT_URL`（覆盖 KB 仓库地址）、`KB_GIT_REF`（覆盖分支或 tag）、
`OFFLINE=1`（跳过在线下载）。
也可以使用 `--offline`。离线模式要求知识库已经存在，并且缺失的在线归档已经在
`<项目>/repos/software-infrastructure-knowledge-base/.cache/` 中。

环境要求：sed、grep、curl、git、python3（仅标准库）、awk、diff，以及
sha256sum / shasum / openssl 任一。脚本不再强制依赖 GNU grep，macOS 自带工具即可。

## 覆盖范围与边界

- 源码语料仅覆盖 MadGraph 3.5.13、Delphes 3.5.0、FastJet 3.3.4；
  Pythia8 等其他软件无源码语料。
- 知识库在目标环境为只读：不要重跑索引构建；语料升级由维护方发布新版迁移包。
