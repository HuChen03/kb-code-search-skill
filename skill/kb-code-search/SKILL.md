---
name: kb-code-search
description: 从本仓库软件知识库（repos/software-infrastructure-knowledge-base）检索 MadGraph/Delphes/FastJet
  源码与手册。当任务涉及这些软件的实现细节、调用方、依赖或测试时使用。
  以 grep 为发现路径（先读 repo-map 确定目录与术语）；Python 符号可直接 grep
  index/symbols.jsonl 取 record id 与精确行区间作引用。不依赖 MCP 服务、向量库、
  额外服务或专用检索模型。
---

# KB Code Search

## 适用范围与边界

- 代码片段检索只覆盖软件 KB，检索根：`repos/software-infrastructure-knowledge-base/`
  （MadGraph 3.5.13、Delphes 3.5.0、FastJet 3.3.4 源码 + 版本化手册，Fortran/Python/C++）。
- 源码树：`source/mg5_aMC_v3.5.13/`、`source/delphes-3.5.0/`、`source/fastjet-3.3.4/`。
  Pythia8 等其他软件**没有源码语料**，涉及其实现细节时直接说明不在覆盖范围。
- `manuals/delphes/cepc-custom/` 是 CEPC 定制版的运行时证据，版本未解析；
  不得用上游 3.5.0 源码结论覆盖定制版行为（KB AGENTS.md 禁止跨版本/跨镜像合并证据）。
- 遵守 `repos/software-infrastructure-knowledge-base/AGENTS.md` 的只读与证据要求：
  知识库只读；技术结论必须引用 `path:起止行号`。
- 索引行号以 `pinned-revisions.json` 的修订为准；磁盘与索引不符时以磁盘为准并注明偏移。

## 检索流程（最多 3 轮，找到 ≥3 个高相关位置即停）

1. **读地图**：先读 `references/repo-map.md`，确定目标子目录与候选代码术语
   （英文标识符，如 insert_decay / boostx / FastJetFinder / ClusterSequence）。
   **纯中文描述无法产生有效检索**；第一轮检索的主要价值是暴露代码库的真实命名，
   读到后立即用它改写 query。
   仅当需要引用索引记录时，先确认 `index/summary.json` 存在且其
   `knowledge_base_revision` 与 `pinned-revisions.json` 一致；不一致则以磁盘为准并注明。
2. **grep 检索**：在地图选定的根下按语言直接检索（一律加 `--exclude-dir=.git --exclude-dir=__pycache__`）。
   多个独立查询（不同术语/不同根）**在同一轮并行发出**，不要串行等待：
   - 定义（Python）：`grep -rnE '^[[:space:]]*(def|class)[[:space:]]+NAME\b' --include='*.py' <root>`
   - 定义（Fortran）：`grep -rniE '^[[:space:]]*([a-z ]*function|subroutine)[[:space:]]+NAME\b' --include='*.F' --include='*.f' <root>`
   - 定义（C/C++）：`grep -rn '\bNAME\b' --include='*.cc' --include='*.hh' --include='*.cpp' --include='*.h' <root>`，
     取命中行 ±20 行作为候选片段，再定位最近的类/函数声明行作为边界；
     命中过多时先按文件聚合计数、文件名含术语者优先，再在头部文件内选定义形态行
     （`::NAME`、`class NAME`、`new NAME`）
   - Delphes 模块（`source/delphes-3.5.0/`）：模块类定义
     `grep -rnE 'class[[:space:]]+NAME[[:space:]]*:[[:space:]]*public[[:space:]]+DelphesModule' --include='*.h' <root>/modules`，
     实现在同名 `modules/NAME.cc`；数据类在 `classes/`，I/O 在 `readers/`；
     `external/` 是捆绑的第三方代码（含 vendored fastjet，版本与 `source/fastjet-3.3.4/` 不同，勿混用）
   - FastJet（`source/fastjet-3.3.4/`）：声明在 `include/fastjet/NAME.hh`，
     实现在 `src/NAME.cc`；工具类（selector/tagger 等）在 `tools/`，算法插件在 `plugins/<插件名>/`。
     用 `grep -rl '\bNAME\b' include --include='*.hh'` 与 `grep -rl '\bNAME\b' src tools plugins --include='*.cc'`
     配对定位声明与实现
   - 构建/安装事实：`--include='Makefile.am' --include='CMakeLists.txt' --include='configure*' --include='*.in'`
   - 手册/文档事实：在 `<root>/manuals`、`<root>/docs`、`<root>/cards` 中检索
     `--include='*.md' --include='*.txt' --include='*.dat'`
   - 调用方：`grep -rlw 'NAME' --include='*.py' --exclude-dir=__pycache__ <root>`（去掉定义文件；C++ 加 `--include='*.cc' --include='*.hh'`）
   - 测试：`grep -rn 'NAME' <root>/tests`（MadGraph）；Delphes 用 `validation/`、`examples/`；
     FastJet 用 `testsuite/`、`regression-tests/`、`example/`
3. **精读**：`sed -n 'START,ENDp' <path>` 读候选区间，判断角色：实现 / 调用方 / 转发 / 注释。
   **匹配行不等于完整实现**：先用 `grep -n 'def \|class \|subroutine '` 找包围符号边界，再 `sed -n` 读全。
4. **引用**：grep 命中的位置以 `path:起-止` 引用。命中索引内 Python 符号时，直接
   `grep -F '"name": "NAME"' <kb-root>/index/symbols.jsonl`（命中多时用模块名/qualified_name
   过滤）取 record id 与精确行区间，citation 写 `<record id> @ <path>:<起>-<止>`；
   未索引内容（Fortran/C/C++ 源码、手册）直接引用并注明"未经索引核实"。

## 异常处理

- **零命中**：① 用第一轮暴露的真实术语或 repo-map 中的同义术语改写查询；② 放宽 `--include` 类型；
  ③ 缩到更具体的子目录（参考 repo-map 的模块划分）；④ 三轮仍无结果则明确报告"语料中未找到"，
  禁止编造路径或片段。报零命中前先确认三棵源码树（mg5_aMC_v3.5.13、delphes-3.5.0、fastjet-3.3.4）
  与 `manuals/` 都已检索，并在报告中注明覆盖范围。
- **结果过多**：先 `grep -rc PATTERN <dir> | sort -rn -t: -k2 | head` 看分布，再按目录 / `--include` /
  整词（`grep -w`）逐级收窄，最后 `| head -30` 抽查确认，再定点展开。
- **片段不完整**：扩大 `sed -n` 窗口重读；沿 `import` / `include` 追一层依赖；需要调用方时回到第 2 步的调用方检索。
- **源码变化**：`symbols.jsonl` 记录的行区间与磁盘内容不符时，以磁盘为准，在引用中注明行号偏移。

## 返回格式

每条命中输出：

```
- path: <仓库相对路径>
  lines: <起>-<止>
  role: implementation | caller | dependency | test
  snippet: <带行号的原始代码片段>
  note: <与需求的对应关系、版本/镜像归属、是否命中 symbols.jsonl 索引记录>
  citation: <record id> @ <path>:<起>-<止>
```

## 完整示例（真实语料，命令与输出均为实跑结果）

需求：「MadSpin 是怎么加载物理模型的？」

```
# 1. 读 references/repo-map.md → MadSpin/：衰变（decay.py、interface_madspin.py，
#    类名如 MadSpinInterface）。候选术语：MadSpinInterface
# 2. grep 定义
$ grep -rnE '^[[:space:]]*(def|class)[[:space:]]+MadSpinInterface\b' --include='*.py' \
    --exclude-dir=.git --exclude-dir=__pycache__ \
    repos/software-infrastructure-knowledge-base/source/mg5_aMC_v3.5.13
.../MadSpin/interface_madspin.py:138:class MadSpinInterface(extended_cmd.Cmd):

# 3. 精读：匹配行只是类声明，模型加载应在方法里 → 文件内再找
$ grep -n 'def .*model' .../MadSpin/interface_madspin.py
1189:    def load_model(self, name, use_mg_default, complex_mass=False):

# 4. 找包围符号边界并读全（sed 输出节选）
$ sed -n '1189,1192p' .../MadSpin/interface_madspin.py
    def load_model(self, name, use_mg_default, complex_mass=False):
        """load the model"""

# 5. 补调用方
$ grep -rlw 'load_model' --include='*.py' --exclude-dir=__pycache__ .../source/mg5_aMC_v3.5.13
...（列出调用方文件）

# 6. 命中索引内 Python 符号，grep symbols.jsonl 取 record id
$ grep -F '"qualified_name": "MadSpin.interface_madspin.MadSpinInterface.load_model"' \
    repos/software-infrastructure-knowledge-base/index/symbols.jsonl | head -1
{"id": "symbol.function.MadSpin.interface_madspin.MadSpinInterface.load_model.line1189", ...}
```

返回：

```
- path: repos/software-infrastructure-knowledge-base/source/mg5_aMC_v3.5.13/MadSpin/interface_madspin.py
  lines: 1189-1213
  role: implementation
  snippet: |
    1189:     def load_model(self, name, use_mg_default, complex_mass=False):
    1190:         """load the model"""
    ...
  note: MadSpinInterface 的模型加载入口；行区间与 symbols.jsonl 索引记录一致
  citation: symbol.function.MadSpin.interface_madspin.MadSpinInterface.load_model.line1189 @ .../interface_madspin.py:1189-1213
```

需求：「Delphes 的 FastJetFinder 是怎么调用 FastJet 的？」（C++ 语料，同一循环）

```
# 1. repo-map → source/delphes-3.5.0/modules/（模块类 : public DelphesModule）
# 2. 定义：
$ grep -rnE 'class[[:space:]]+FastJetFinder[[:space:]]*:[[:space:]]*public[[:space:]]+DelphesModule' \
    --include='*.h' repos/software-infrastructure-knowledge-base/source/delphes-3.5.0/modules
.../modules/FastJetFinder.h:51:class FastJetFinder: public DelphesModule

# 3. 同名实现文件内找 FastJet 调用点：
$ grep -n 'ClusterSequence\|JetDefinition' .../modules/FastJetFinder.cc
51:#include "fastjet/ClusterSequence.hh"
95:  JetDefinition::Plugin *plugin = 0;
...

# 4. 需要 FastJet 侧实现时跳到 source/fastjet-3.3.4/：
#    include/fastjet/JetDefinition.hh:250 声明，src/JetDefinition.cc 实现
```

返回时 `note` 注明"未经索引核实（C++ 无符号索引）"，`citation` 直接写
`.../FastJetFinder.cc:<起>-<止>`。

Fortran 语料（如 HELAS 的洛伦兹 boost）走同一循环，定义模式换成
`grep -rniE '^[[:space:]]*subroutine[[:space:]]+boostx\b' --include='*.F'`，
命中 `HELAS/boostx.F:1` 后用 `subroutine`/`end` 定边界。
