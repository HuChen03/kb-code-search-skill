#!/usr/bin/env bash
# ============================================================================
# kb-code-search 一键迁移脚本
#
# 用法:
#   ./migrate.sh [--dir <项目文件夹>] [--agent auto|kimi|claude|codex|all]
#   ./migrate.sh <项目文件夹> [--agent ...]   # 兼容旧用法
#
# 目标文件夹是用户打开的项目根目录。脚本会创建统一布局:
#   <项目>/repos/software-infrastructure-knowledge-base/
#   <项目>/.codex/skills/kb-code-search/       # 取决于 --agent
#
# 环境变量:
#   KB_GIT_URL   覆盖知识库仓库地址
#   KB_GIT_REF   覆盖知识库分支或 tag
#   OFFLINE=1    只使用本地已有的知识库和归档
# ============================================================================
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
用法:
  migrate.sh [--dir <项目文件夹>] [--agent auto|kimi|claude|codex|all]
  migrate.sh <项目文件夹> [--agent ...]   # 兼容旧用法

选项:
  --dir DIR       项目根目录，默认当前目录
  --agent AGENT   安装到 codex、claude、kimi、all 或 auto，默认 codex
  --offline       不联网，只使用已有的 Git 仓库和归档缓存
  -h, --help      显示帮助
EOF
    exit "${1:-2}"
}

TARGET=""
AGENT="codex"
OFFLINE="${OFFLINE:-0}"

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)
            [ $# -ge 2 ] || usage
            TARGET="$2"
            shift 2
            ;;
        --agent)
            [ $# -ge 2 ] || usage
            AGENT="$2"
            shift 2
            ;;
        --offline)
            OFFLINE=1
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        --*)
            usage
            ;;
        *)
            [ -z "$TARGET" ] || usage
            TARGET="$1"
            shift
            ;;
    esac
done

TARGET="${TARGET:-.}"
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd -P)"

case "$AGENT" in
    kimi)   SKILL_SUBDIRS='.agents/skills' ;;
    claude) SKILL_SUBDIRS='.claude/skills' ;;
    codex)  SKILL_SUBDIRS='.codex/skills' ;;
    all)    SKILL_SUBDIRS='.codex/skills
.claude/skills
.agents/skills' ;;
    auto)
        if [ -d "$TARGET/.codex" ]; then
            SKILL_SUBDIRS='.codex/skills'
        elif [ -d "$TARGET/.claude" ]; then
            SKILL_SUBDIRS='.claude/skills'
        elif [ -d "$TARGET/.agents" ]; then
            SKILL_SUBDIRS='.agents/skills'
        else
            SKILL_SUBDIRS='.codex/skills'
        fi
        ;;
    *)
        echo "ERROR: 未知 agent 类型: $AGENT（可选 auto|kimi|claude|codex|all）" >&2
        exit 2
        ;;
esac

OVERLAY="$(cd "$(dirname "$0")" && pwd -P)"
MANIFEST="$OVERLAY/manifest.json"
KB="$TARGET/repos/software-infrastructure-knowledge-base"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -f "$MANIFEST" ] || die "缺少 manifest.json: $MANIFEST"
command -v python3 >/dev/null 2>&1 || die "缺少命令: python3"

manifest_scalar() { # <key> 或 index.asset
    python3 - "$MANIFEST" "$1" <<'PY'
import json
import sys

manifest_path, key = sys.argv[1:]
with open(manifest_path, encoding="utf-8") as handle:
    data = json.load(handle)
value = data
for part in key.split("."):
    value = value[part]
if not isinstance(value, (str, int)):
    raise SystemExit(f"manifest key is not scalar: {key}")
print(value)
PY
}

archive_rows() {
    python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
for item in data["archives"]:
    print("|".join([
        item["name"],
        item.get("url") or "",
        item["sha256"],
        item["target"],
    ]))
PY
}

KB_GIT_URL="${KB_GIT_URL:-$(manifest_scalar knowledge_base.url)}"
KB_GIT_REF="${KB_GIT_REF:-$(manifest_scalar knowledge_base.ref)}"
INDEX_KB_REVISION="$(manifest_scalar index.knowledge_base_revision)"
INDEX_ASSET="$(manifest_scalar index.asset)"
INDEX_SHA256="$(manifest_scalar index.sha256)"
SKILL_SOURCE="$OVERLAY/$(manifest_scalar skill_path)"
[ -d "$SKILL_SOURCE" ] || die "skill 目录不存在: $SKILL_SOURCE"

for command_name in awk cat cmp cp curl date diff find git grep mkdir mktemp mv rm rmdir sed
do
    command -v "$command_name" >/dev/null 2>&1 || die "缺少命令: $command_name"
done

if command -v sha256sum >/dev/null 2>&1; then
    _sha256() { sha256sum "$1"; }
elif command -v shasum >/dev/null 2>&1; then
    _sha256() { LC_ALL=C shasum -a 256 "$1"; }
elif command -v openssl >/dev/null 2>&1; then
    _sha256() { openssl dgst -sha256 -r "$1"; }
else
    die "缺少 sha256 校验工具（sha256sum / shasum / openssl 任一即可）"
fi

verify_sha256() { # <expected> <file>
    [ "$(_sha256 "$2" | awk '{print $1}')" = "$1" ]
}

backup_move() { # <path>；保留旧内容，不删除
    local path="$1"
    [ -e "$path" ] || return 0

    local stamp backup suffix
    stamp="$(date +%Y%m%d%H%M%S)"
    backup="${path}.backup.${stamp}"
    suffix=0
    while [ -e "$backup" ]; do
        suffix=$((suffix + 1))
        backup="${path}.backup.${stamp}.${suffix}"
    done
    mv "$path" "$backup"
    echo "    已保留旧版本: $backup"
}

fetch_archive() { # <url> <sha256> <output>
    local url="$1" expected="$2" output="$3"
    mkdir -p "$(dirname "$output")"
    if [ -f "$output" ] && verify_sha256 "$expected" "$output"; then
        echo "    cached: $(basename "$output")"
        return
    fi
    [ "$OFFLINE" = "1" ] && die "OFFLINE=1 且缓存缺失或校验失败: $output"

    echo "    downloading: $url"
    curl -fsSL --retry 5 --connect-timeout 15 --max-time 900 \
        -o "$output.part" "$url"
    verify_sha256 "$expected" "$output.part" || {
        rm -f "$output.part"
        die "校验和不匹配: $url"
    }
    mv "$output.part" "$output"
}

extract_archive() { # <tarball> <target-dir>
    local tarball="$1" target="$2"
    local parent base stage extracted
    parent="$(dirname "$target")"
    base="$(basename "$target")"
    mkdir -p "$parent"
    stage="$(mktemp -d "$parent/.${base}.staging.XXXXXX")"

    if ! extracted="$(TARBALL="$tarball" STAGING="$stage" python3 - <<'PY'
import os
import tarfile
from pathlib import Path

archive = Path(os.environ["TARBALL"])
root = Path(os.environ["STAGING"]).resolve()
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
    try:
        tar.extractall(root, filter="data")
    except TypeError:  # Python < 3.12
        tar.extractall(root)

top = [path for path in root.iterdir()]
if len(top) == 1 and top[0].is_dir():
    print(top[0])
else:
    print(root)
PY
)"; then
        rm -R "$stage"
        die "解包失败: $tarball"
    fi

    backup_move "$target"
    mv "$extracted" "$target"
    if [ "$extracted" != "$stage" ]; then
        rmdir "$stage"
    fi
}

install_skill() { # <skill-subdir>
    local subdir="$1"
    local destination="$TARGET/$subdir/kb-code-search"
    local parent stage
    parent="$(dirname "$destination")"
    mkdir -p "$parent"

    if [ -d "$destination" ] && diff -qr "$SKILL_SOURCE" "$destination" >/dev/null 2>&1; then
        echo "    skill 已是最新: $destination"
        return
    fi

    stage="$(mktemp -d "$parent/.kb-code-search.staging.XXXXXX")"
    cp -R "$SKILL_SOURCE" "$stage/kb-code-search"
    backup_move "$destination"
    mv "$stage/kb-code-search" "$destination"
    rmdir "$stage"
    echo "    installed: $destination"
}

echo "==> [0/6] 环境检查"
echo "    项目目录: $TARGET"
echo "    agent: $AGENT"

echo "==> [1/6] 知识库仓库"
mkdir -p "$TARGET/repos"
if [ -d "$KB/.git" ]; then
    echo "    已存在，跳过 clone: $KB"
elif [ -e "$KB" ]; then
    [ -z "$(find "$KB" -mindepth 1 -maxdepth 1 -print -quit)" ] || \
        die "$KB 已存在且非空但不是 Git 仓库；为保护数据未覆盖"
    rmdir "$KB"
    [ "$OFFLINE" = "1" ] && die "OFFLINE=1 但知识库仓库不存在: $KB"
    git clone --quiet --branch "$KB_GIT_REF" "$KB_GIT_URL" "$KB"
    echo "    cloned: $(git -C "$KB" log --oneline -1)"
else
    [ "$OFFLINE" = "1" ] && die "OFFLINE=1 但知识库仓库不存在: $KB"
    git clone --quiet --branch "$KB_GIT_REF" "$KB_GIT_URL" "$KB"
    echo "    cloned: $(git -C "$KB" log --oneline -1)"
fi

echo "==> [2/6] 源码归档（下载/校验/解包）"
mkdir -p "$KB/.cache"
while IFS='|' read -r name url sha256 target; do
    [ -n "$name" ] || continue
    stamp="$KB/$target/.source-archive-sha256"
    if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sha256" ]; then
        echo "    extracted: $target (up to date)"
        continue
    fi

    if [ -n "$url" ]; then
        fetch_archive "$url" "$sha256" "$KB/.cache/$name"
        tarball="$KB/.cache/$name"
    else
        tarball="$OVERLAY/$name"
        [ -f "$tarball" ] || die "包内归档缺失: $name"
        verify_sha256 "$sha256" "$tarball" || die "包内归档损坏: $name"
        echo "    bundled: $name"
    fi

    extract_archive "$tarball" "$KB/$target"
    printf '%s\n' "$sha256" > "$stamp"
    echo "    extracted: $target"
done < <(archive_rows)

echo "==> [3/6] 索引快照"
index_ready=0
if [ -f "$KB/index/summary.json" ] && \
   grep -Fq "\"knowledge_base_revision\": \"$INDEX_KB_REVISION\"" "$KB/index/summary.json"; then
    index_ready=1
    echo "    index 已是最新: $KB/index"
fi
if [ "$index_ready" = "0" ]; then
    index_tarball="$OVERLAY/$INDEX_ASSET"
    [ -f "$index_tarball" ] || die "索引归档缺失: $index_tarball"
    verify_sha256 "$INDEX_SHA256" "$index_tarball" || die "索引归档损坏: $index_tarball"
    extract_archive "$index_tarball" "$KB/index"
    echo "    restored: $INDEX_ASSET"
fi

echo "==> [4/6] 安装 skill"
while IFS= read -r subdir; do
    [ -n "$subdir" ] || continue
    install_skill "$subdir"
done <<EOF
$SKILL_SUBDIRS
EOF

echo "==> [5/6] pinned-revisions.json"
if [ ! -f "$KB/pinned-revisions.json" ] || \
   ! cmp -s "$OVERLAY/pinned-revisions.json" "$KB/pinned-revisions.json"; then
    cp "$OVERLAY/pinned-revisions.json" "$KB/pinned-revisions.json"
    echo "    written: $KB/pinned-revisions.json"
else
    echo "    pinned-revisions.json 已是最新"
fi

echo "==> [6/6] 自检"
actual="$(python3 -c "import json; print(json.load(open('$KB/index/summary.json'))['knowledge_base_revision'])")"
[ "$actual" = "$INDEX_KB_REVISION" ] || die "索引修订不一致: $actual != $INDEX_KB_REVISION"
echo "    索引修订一致: $actual"

grep -rnE 'class[[:space:]]+FastJetFinder[[:space:]]*:[[:space:]]*public[[:space:]]+DelphesModule' \
    "$KB/source/delphes-3.5.0/modules" | grep -q 'FastJetFinder.h:51:' \
    || die "Delphes 源码自检失败"
echo "    Delphes 源码检索 OK (FastJetFinder.h:51)"

sed -n '1189p' "$KB/source/mg5_aMC_v3.5.13/MadSpin/interface_madspin.py" | \
    grep -q 'def load_model' || die "MG5 源码自检失败"
grep -Fq '"qualified_name": "MadSpin.interface_madspin.MadSpinInterface.load_model"' \
    "$KB/index/symbols.jsonl" || die "符号索引自检失败"
echo "    MG5 源码 + 符号索引 OK (interface_madspin.py:1189)"

[ -f "$KB/source/fastjet-3.3.4/include/fastjet/JetDefinition.hh" ] || \
    die "FastJet 源码自检失败"
echo "    FastJet 源码 OK (JetDefinition.hh)"

echo
echo "迁移完成。项目目录: $TARGET"
echo "提示: 旧目录在更新时会保留为 *.backup.<时间戳>，不会默认删除用户数据。"
