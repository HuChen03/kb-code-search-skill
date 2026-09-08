# Repo Map（检索地图）

用途：检索前确定候选目录与术语。只列"什么东西在哪、叫什么"；结论与引用必须
回到真实文件核实。本地图对应 pinned-revisions.json 中
software-infrastructure-knowledge-base 的修订，修订变化时须刷新。

检索根：`repos/software-infrastructure-knowledge-base/`

## source/mg5_aMC_v3.5.13/（MadGraph 3.5.13 源码，约 4800 个文件）

- `madgraph/`：主框架 Python 包
  - `core/`：图、振幅、helas 对象（helas_objects.py、diagram_generation.py）
  - `interface/`：命令行接口（madgraph_interface.py）
  - `iolibs/`：导出；`various/`：工具（misc.py 等）
- `MadSpin/`：衰变（decay.py、interface_madspin.py，类名如 MadSpinInterface）
- `aloha/`：振幅例程生成；`models/`：UFO 模型；`mg5decay/`：衰变宽度
- `HELAS/`：Fortran 螺旋度振幅库（subroutine 命名如 boostx、iovxxx，*.F）
- `Template/`：生成代码模板；`vendor/`：第三方；`tests/`：测试（含 input_files/ 期望输出）

## source/delphes-3.5.0/（Delphes 3.5.0 源码，828 个文件，C++ 为主）

- `modules/`：探测器模拟模块，类形态 `class X: public DelphesModule`
  （X.h 声明 + X.cc 实现同名配对，如 FastJetFinder、Calorimeter、BTagging）
- `classes/`：数据类（DelphesClasses.h、ClassesLinkDef.h，ROOT 字典）
- `readers/`：输入读取（DelphesHepMC3.cpp、DelphesLHEF.cpp、DelphesProIO.cpp 等）
- `converters/`、`display/`、`python/`：格式转换、事件显示、Python 绑定
- `cards/`：探测器配置卡（*.tcl）；`examples/`：用法示例；`validation/`：验证宏
- `external/`：捆绑第三方（ExRootAnalysis、PUPPI、TrackCovariance、vendored fastjet、tcl；
  其 fastjet 版本与 `source/fastjet-3.3.4/` 不同，勿混用）

## source/fastjet-3.3.4/（FastJet 3.3.4 源码，527 个文件，C++）

- `include/fastjet/`：公开头文件（NAME.hh 声明，如 JetDefinition.hh、ClusterSequence.hh、Selector.hh）
- `src/`：实现（NAME.cc，与头文件同名配对）
- `tools/`：工具类（Filter、JHTopTagger、GridMedianBackgroundEstimator 等）
- `plugins/<插件名>/`：算法插件（ATLASCone、CDFCones、EECambridge、Jade、D0RunICone 等，
  每个插件有自己的 include/src 子层）
- `example/`：教程示例（01-basic.cc 起编号）；`testsuite/`、`regression-tests/`：测试
- 构建系统：autotools（`configure.ac`、`Makefile.am`），`pyinterface/` 是 Python 绑定

## 索引（index/，直接 grep，不走任何外部服务）

- `symbols.jsonl`：5802 条 Python 符号（class/function），带 record id 与精确行区间——
  查 Python 实现首选 `grep -F '"qualified_name": "<模块.符号>"' index/symbols.jsonl`
- `files.jsonl`：2137 条源码文件记录（三棵源码树的文件清单，C++ 文件也有 file 级记录）
- `documents.jsonl`：118 条文档分块
- `summary.json`：索引元信息（`knowledge_base_revision` 应与 pinned-revisions.json 一致）
- Fortran/C/C++ 无符号索引（无精确行区间），只能 grep，引用注明"未经索引核实"

## 手册与文档（未入符号索引，grep --include='*.md' --include='*.txt'）

- `manuals/madgraph/3.5.13`、`manuals/madgraph/3.6.7`：MadGraph 版本化手册
- `manuals/delphes/3.5.0/`：Delphes 手册（quick-start.md、review.md）；
  `manuals/delphes/cepc-custom/`：CEPC 定制版接口文档（版本未解析的运行时证据，
  与上游 3.5.0 源码结论不可互相覆盖）
- `manuals/fastjet/3.3.4/`：FastJet 手册（api-review.md、version-evidence.txt）
- `docs/`：KB 设计文档；`cards/`：过程卡/参数卡示例；`validate/`：验证脚本

## 其他

- `models/my_sm/`：自定义 UFO 模型（Python，已入符号索引）
- `papers/`：论文摘要（设计背景，不是软件行为的一手证据）
