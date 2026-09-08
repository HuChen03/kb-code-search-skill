#!/usr/bin/env bash
# ============================================================================
# kb-code-search 一键迁移脚本
#
# 用法:
#   ./migrate.sh <目标文件夹> [--agent kimi|claude|codex]
#
# 行为:
#   把软件知识库仓库直接克隆到 <目标文件夹>，补齐源码树与索引，
#   并把检索 skill 安装到该文件夹下对应 agent 的 skill 目录:
#     kimi   → <目标文件夹>/.agents/skills/kb-code-search   （Kimi Code 项目级约定）
#     claude → <目标文件夹>/.claude/skills/kb-code-search
#     codex  → <目标文件夹>/.codex/skills/kb-code-search
#   直接用 agent 打开 <目标文件夹> 即可使用（skill 内的检索根已改写为 ./）。
#
# 环境变量（均可选）:
#   KB_GIT_URL   KB 仓库地址（默认 GitHub 上的公开仓库）
#   OFFLINE=1    跳过 git clone 与在线下载（要求仓库已就位、源码归档已在缓存）
#
# 环境要求: GNU grep、sed、tar、curl、git、python3（仅标准库），
#           以及 sha256sum / shasum / openssl 任一（校验用）。
# macOS 注意: 需 brew install gnu-grep，并把 skill 文件中的 grep 换成 ggrep。
#
# 说明:
#   - 本脚本不修改 KB 仓库的 git 内容，只添加 gitignore 覆盖的产物
#     （source/、index/、.cache/）和 untracked 的 skill 目录。
#   - MG5 pinned 归档随包携带：上游 launchpad 已不再提供该构建，GitHub tag
#     树缺少 release 生成文件，与索引不一致。
#   - KB 在目标环境只读：不要重跑 KB 里的 build_index.py（它依赖原
#     benchmark-image workspace）；语料升级由原维护方发布新版迁移包。
#   - 索引中 my_sm 模型的少量记录指向原 benchmark-image 仓库路径，目标环境
#     没有该仓库时这部分引用失效；其余 5802 条 Python 符号记录不受影响。
# ============================================================================
set -euo pipefail

usage() {
    echo "用法: $0 <目标文件夹> [--agent kimi|claude|codex]" >&2
    echo "环境变量: KB_GIT_URL / OFFLINE=1（详见脚本头部注释）" >&2
    exit 2
}

[ $# -ge 1 ] || usage
TARGET="$1"; shift
AGENT="kimi"
while [ $# -gt 0 ]; do
    case "$1" in
        --agent) [ $# -ge 2 ] || usage; AGENT="$2"; shift 2 ;;
        *) usage ;;
    esac
done

case "$AGENT" in
    kimi)   SKILL_SUBDIR=".agents/skills" ;;
    claude) SKILL_SUBDIR=".claude/skills" ;;
    codex)  SKILL_SUBDIR=".codex/skills" ;;
    *) echo "ERROR: 未知 agent 类型: $AGENT（可选 kimi|claude|codex）" >&2; exit 2 ;;
esac

OVERLAY="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$TARGET"
KB="$(cd "$TARGET" && pwd)"
SKILL_DIR="$KB/$SKILL_SUBDIR/kb-code-search"
KB_GIT_URL="${KB_GIT_URL:-https://github.com/SII-inpac-Chuangqi/software-infrastructure-knowledge-base.git}"
OFFLINE="${OFFLINE:-0}"

KB_REVISION="070f1eacd7da13417ed520052c538a3c0115c38a"
INDEX_ASSET="index-070f1ea.tar.gz"
INDEX_SHA256="d31d3b204b4f54fd964716b5df61a50517912595e5475335c5cf262b6fe2580b"

# 源码归档清单: <tarball>|<url（空=随包携带）>|<sha256>|<解压目标>
ARCHIVES=$(cat <<'EOF'
MG5_aMC_v3.5.13.tar.gz||55ac5517eacde69d37a22ef2677a923a597b34b04578df9fe76519afaab088a2|source/mg5_aMC_v3.5.13
delphes-3.5.0.tar.gz|https://github.com/delphes/delphes/archive/refs/tags/3.5.0.tar.gz|30a2536e0c8f47d633ecf3b4d51ec9924af54538e492470ad47b4ed34342f063|source/delphes-3.5.0
fastjet-3.3.4.tar.gz|https://gitlab.com/fastjet/fastjet/-/archive/fastjet-3.3.4/fastjet-fastjet-3.3.4.tar.gz|a5ebeb9d5390fb6810bb1fdcae7b876ed6b48075cf4ad5cb283bc59c4b42b46f|source/fastjet-3.3.4
EOF
)

die() { echo "ERROR: $*" >&2; exit 1; }

echo "==> [0/6] 环境检查"
grep --version 2>/dev/null | grep -q GNU || die "需要 GNU grep（macOS 请 brew install gnu-grep）"
for cmd in sed tar curl git python3; do
    command -v "$cmd" >/dev/null || die "缺少命令: $cmd"
done

# sha256 校验兼容层：sha256sum（Linux）→ shasum（macOS）→ openssl
if command -v sha256sum >/dev/null 2>&1; then
    _sha256() { sha256sum "$1"; }
elif command -v shasum >/dev/null 2>&1; then
    _sha256() { shasum -a 256 "$1"; }
elif command -v openssl >/dev/null 2>&1; then
    _sha256() { openssl dgst -sha256 -r "$1"; }
else
    die "缺少 sha256 校验工具（sha256sum / shasum / openssl 任一即可）"
fi
verify_sha256() { # <expected> <file>
    [ "$(_sha256 "$2" | awk '{print $1}')" = "$1" ]
}

echo "==> [1/6] 知识库仓库"
if [ -d "$KB/.git" ]; then
    echo "    已存在，跳过 clone: $KB"
else
    [ "$OFFLINE" = "1" ] && die "OFFLINE=1 但 $KB 不是 git 仓库"
    [ -z "$(ls -A "$KB")" ] || die "$KB 非空且不是 git 仓库，请换空目录"
    git clone --quiet "$KB_GIT_URL" "$KB"
    echo "    cloned: $(git -C "$KB" log --oneline -1)"
fi

fetch() { # <url> <sha256> <output>
    local url="$1" expected="$2" out="$3"
    if [ -f "$out" ] && verify_sha256 "$expected" "$out" 2>/dev/null; then
        echo "    cached: $(basename "$out")"
        return
    fi
    [ "$OFFLINE" = "1" ] && die "OFFLINE=1 且缓存缺失: $out"
    echo "    downloading: $url"
    curl -fsSL --retry 3 -o "$out.part" "$url"
    verify_sha256 "$expected" "$out.part" || {
        rm -f "$out.part"; die "校验和不匹配: $url"
    }
    mv "$out.part" "$out"
}

extract() { # <tarball> <target-dir>
    local tarball="$1" target="$2"
    rm -rf "$target"
    mkdir -p "$(dirname "$target")"
    TARBALL="$tarball" TARGET_DIR="$target" python3 - <<'EOF'
import os, shutil, tarfile, tempfile
from pathlib import Path

archive, destination = Path(os.environ["TARBALL"]), Path(os.environ["TARGET_DIR"])
with tempfile.TemporaryDirectory(dir=destination.parent) as staging:
    root = Path(staging).resolve()
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            member_target = (root / member.name).resolve()
            if member_target != root and root not in member_target.parents:
                raise SystemExit(f"unsafe archive member: {member.name}")
            if member.issym() or member.islnk():
                link = Path(member.linkname)
                resolved = (member_target.parent / link).resolve() if not link.is_absolute() else link.resolve()
                if resolved != root and root not in resolved.parents:
                    raise SystemExit(f"unsafe archive link: {member.name}")
        tar.extractall(root)
    top = list(root.iterdir())
    if len(top) == 1 and top[0].is_dir():
        shutil.move(str(top[0]), destination)
    else:
        shutil.move(staging, destination)
EOF
}

echo "==> [2/6] 源码归档（下载/校验/解包）"
mkdir -p "$KB/.cache"
echo "$ARCHIVES" | while IFS='|' read -r name url sha256 target; do
    if [ -n "$url" ]; then
        fetch "$url" "$sha256" "$KB/.cache/$name"
        tarball="$KB/.cache/$name"
    else
        tarball="$OVERLAY/$name"
        verify_sha256 "$sha256" "$tarball" || die "包内归档损坏: $name"
        echo "    bundled: $name"
    fi
    stamp="$KB/$target/.source-archive-sha256"
    if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sha256" ]; then
        echo "    extracted: $target (up to date)"
    else
        extract "$tarball" "$KB/$target"
        echo "$sha256" > "$stamp"
        echo "    extracted: $target"
    fi
done

echo "==> [3/6] 索引快照"
verify_sha256 "$INDEX_SHA256" "$OVERLAY/$INDEX_ASSET" || die "索引快照损坏"
rm -rf "$KB/index"
mkdir -p "$KB/index"
tar xzf "$OVERLAY/$INDEX_ASSET" -C "$KB/index"
echo "    restored: $INDEX_ASSET"

echo "==> [4/6] 安装 skill（$AGENT → $SKILL_SUBDIR/）"
mkdir -p "$(dirname "$SKILL_DIR")"
rm -rf "$SKILL_DIR"
cp -r "$OVERLAY/skill/kb-code-search" "$SKILL_DIR"
# skill 内的检索根从原 workspace 相对路径改写为当前文件夹自身
for f in "$SKILL_DIR/SKILL.md" "$SKILL_DIR/references/repo-map.md"; do
    sed 's|repos/software-infrastructure-knowledge-base/|./|g; s|检索根：`./`|检索根：`.`（本文件夹即知识库根）|' "$f" > "$f.tmp"
    mv "$f.tmp" "$f"
done
echo "    installed: $SKILL_DIR（检索根已改写为 ./）"

echo "==> [5/6] pinned-revisions.json"
cp "$OVERLAY/pinned-revisions.json" "$KB/pinned-revisions.json"
echo "    written: $KB/pinned-revisions.json"

echo "==> [6/6] 自检"
actual=$(python3 -c "import json; print(json.load(open('$KB/index/summary.json'))['knowledge_base_revision'])")
[ "$actual" = "$KB_REVISION" ] || die "索引修订不一致: $actual != $KB_REVISION"
echo "    索引修订一致: $actual"

grep -rnE 'class[[:space:]]+FastJetFinder[[:space:]]*:[[:space:]]*public[[:space:]]+DelphesModule' \
    --include='*.h' "$KB/source/delphes-3.5.0/modules" | grep -q 'FastJetFinder.h:51:' \
    || die "Delphes 源码自检失败"
echo "    Delphes 源码检索 OK (FastJetFinder.h:51)"

sed -n '1189p' "$KB/source/mg5_aMC_v3.5.13/MadSpin/interface_madspin.py" | grep -q 'def load_model' \
    || die "MG5 源码自检失败"
grep -Fq '"qualified_name": "MadSpin.interface_madspin.MadSpinInterface.load_model"' \
    "$KB/index/symbols.jsonl" || die "符号索引自检失败"
echo "    MG5 源码 + 符号索引 OK (interface_madspin.py:1189)"

[ -f "$KB/source/fastjet-3.3.4/include/fastjet/JetDefinition.hh" ] || die "FastJet 源码自检失败"
echo "    FastJet 源码 OK (JetDefinition.hh)"

grep -q '检索根：`.`' "$SKILL_DIR/SKILL.md" || die "skill 检索根改写失败"
echo "    skill 检索根 OK (./)"

echo
echo "迁移完成。用 $AGENT 打开文件夹即可使用: $KB"
echo "提示: KB 语料覆盖 MadGraph 3.5.13 / Delphes 3.5.0 / FastJet 3.3.4；知识库只读。"
