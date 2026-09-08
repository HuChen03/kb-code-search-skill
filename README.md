# kb-code-search-skill

软件知识库代码检索 Skill 的一键迁移包。面向 MadGraph 3.5.13 / Delphes 3.5.0 /
FastJet 3.3.4 的源码与手册检索，以 grep 为发现路径，不依赖 MCP 服务、向量库
或专用检索模型。

## 包内容

- `migrate.sh`：一键迁移脚本（clone 知识库仓库、下载/校验/解包源码归档、恢复索引快照、安装 skill）
- `skill/kb-code-search/`：skill 本体（`SKILL.md` + `references/repo-map.md` 检索地图）
- `MG5_aMC_v3.5.13.tar.gz`：MadGraph pinned 源码归档（随包携带，上游已不再提供该构建）
- `index-070f1ea.tar.gz`：Python 符号索引快照（约 5800 条记录）
- `pinned-revisions.json`：各仓库修订与归档 sha256 校验和

## 用法

```bash
./migrate.sh <目标文件夹> [--agent kimi|claude|codex]
```

脚本会把软件知识库（[software-infrastructure-knowledge-base](https://github.com/SII-inpac-Chuangqi/software-infrastructure-knowledge-base)）
克隆到目标文件夹，补齐源码树与索引，并把检索 skill 安装到对应 agent 的 skill
目录（kimi → `.agents/skills/`，claude → `.claude/skills/`，codex → `.codex/skills/`）。
之后用对应 agent 打开该文件夹即可使用。

可选环境变量：`KB_GIT_URL`（覆盖 KB 仓库地址）、`OFFLINE=1`（跳过在线下载）。

环境要求：GNU grep、sed、tar、curl、git、python3（仅标准库），以及
sha256sum / shasum / openssl 任一。macOS 需 `brew install gnu-grep`。

## 覆盖范围与边界

- 源码语料仅覆盖 MadGraph 3.5.13、Delphes 3.5.0、FastJet 3.3.4；
  Pythia8 等其他软件无源码语料。
- 知识库在目标环境为只读：不要重跑索引构建；语料升级由维护方发布新版迁移包。
