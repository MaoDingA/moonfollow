# moonfollow 项目规则

本项目使用 **MoonBit** 实现。

## 强制规则：MoonBit 代码必须遵循官方 Skill

**后续所有的 MoonBit 实现代码（`.mbt` 文件、`moon.mod.json`、`moon.pkg` 配置、构建/测试/文档脚本等）必须遵循 MoonBit 官方提供的 Agent Skills。**

官方 skills 已安装在 `.agents/skills/` 目录下，来源为官方仓库 [moonbitlang/skills](https://github.com/moonbitlang/skills)。编写、修改或审查任何 MoonBit 代码之前，必须先加载对应 skill 并按其规范执行；不得凭旧印象或类 Rust/OCaml 的语法惯性编写 MoonBit 代码。

### Skill 路由表

| 场景 | 必须使用的 skill |
|---|---|
| 编写/组织/测试 MoonBit 项目、moon 工具链（build/check/run/test/doc/ide）、目录布局与命名约定 | `moonbit-agent-guide` |
| 查语言特性、API、编译诊断、工具链、"MoonBit 有没有 X" 等问题 | `moonbit-orientation` |
| 重构 MoonBit 代码使其更惯用（收缩公开 API、转方法、view 模式匹配等） | `moonbit-refactoring` |
| 调用 C 库（extern "c"、native-stub、所有权标注 #borrow/#owned） | `moonbit-c-binding` |
| 为 C/C++ 库做完整 MoonBit 绑定（vendoring、API 设计、ASan 验证） | `make-moonbit-c-bindings` |
| 契约优先开发：搭建 spec.mbt 与 spec 驱动测试 | `moonbit-spec-test-development` |
| 从既有实现提取 spec 与测试套件 | `moonbit-extract-spec-test` |
| 编写/重构证明携带代码（Why3、不变式、断言） | `moonbit-proof` |
| 从 OCaml 迁移代码到 MoonBit | `ocaml2moonbit-migration` |

### 执行要求

1. **写码前先读 skill**：涉及 MoonBit 的实现任务，动手前先读取 `.agents/skills/` 下对应 skill 的 `SKILL.md`（及其引用的 references 文档），按其中约定执行。
2. **工具链命令以 skill 为准**：构建、测试、检查、文档等命令（如 `moon check`、`moon test`、`moon ide`）的用法以 skill 中给出的为准，不自造参数。
3. **API 拿不准时用 `moon ide` 查询**（见 `moonbit-orientation`），不猜测、不沿用过时语法。
4. **遇到诊断/编译错误**：按 `moonbit-orientation` 中的 diagnostics-playbook 定位，不盲改。
5. 更新或新增 skill 时，保持与官方仓库 [moonbitlang/skills](https://github.com/moonbitlang/skills) 同步，不私自改动其内容。

## 工程约定（本项目）

- 模块 `phenom8010/moonfollow`，`moon.mod` 使用新格式，`preferred_target = "native"`。
- 每个包目录一个 `moon.pkg`；测试用黑盒 `*_test.mbt` + `inspect`/`debug_inspect` 快照。
- 代码块以 `///|` 分隔；接口文件 `pkg.generated.mbti` 由 `moon info` 生成，勿手改。
- 提交前跑 `moon check`、`moon test`、`moon fmt`、`moon info`。
- CLI 入口 `cmd/moonfollow`（`moon run cmd/moonfollow -- <subcommand>`）；
  文件 IO 走 `internal/fsio`（native C stub，修改 FFI 时先读 `moonbit-c-binding` skill）。
- `detect/foottrack.py` 是唯一的非 MoonBit 代码（姿态检测外部环节），不改成 MoonBit。
