# HekiliHelper - Gemini 上下文 (Instructional Context)

HekiliHelper 是一个魔兽世界（怀旧服/WLK）插件，旨在增强 **Hekili** 技能循环辅助插件的功能。它为 Hekili 原生系统未涵盖的治疗职业逻辑和实用功能指示器提供专门的支持。

## 项目概览

- **类型:** 魔兽世界插件 (Lua)
- **主要框架:** [Ace3](https://www.curseforge.com/wow/addons/ace3) (包括 AceAddon, AceDB, AceConfig, AceEvent)。
- **核心机制:** 通过挂钩 (Hook) `Hekili.Update` 函数，将自定义的动作推荐注入到 `Hekili.DisplayPool` 中。
- **目标接口版本:** `30400` (怀旧服版本 / WLK)。

### 系统架构

1.  **入口文件 (`HekiliHelper.lua`):** 初始化 Ace3 插件对象，设置数据库存档 (`HekiliHelperDB`)，并管理调试系统。
2.  **模块化设计:** 功能逻辑拆分在 `Modules/` 目录中：
    - `Options.lua`: 使用 `AceConfig-3.0` 定义配置界面，并将其集成到 Hekili 自身的选项菜单中。
    - `MeleeTargetIndicator.lua`: 当玩家身边有敌人但未选中目标或目标超出范围时，在 Hekili 界面显示“近战目标”提示。
    - `HealingShamanSkills.lua` / `HealingPriestSkills.lua`: 为萨满和牧师实现复杂的治疗逻辑（包括智能目标选择、基于血量阈值的技能推荐）。
    - `UIModifier.lua`: 对 Hekili 的 UI 元素进行微调，以实现更好的集成效果。
3.  **挂钩策略:** 使用自定义的 `HookUtils` (位于 `HekiliHelper.lua`) 包装 `Hekili.Update`。通常配合 `C_Timer.After(0.001, ...)` 的微小延迟使用，以确保在 Hekili 完成自身计算之后、UI 渲染之前执行自定义注入。

## 开发约定

- **全局对象:** 主插件对象存储在 `_G.HekiliHelper`。
- **调试系统:**
    - 使用 `HekiliHelper:DebugPrint(message)` 记录日志。
    - 游戏内通过 `/hhdebugwin` 开启专用的调试窗口。
    - 控制台命令: `/hhdebug` (切换调试模式), `/hhlist` (打印当前推荐队列详情)。
- **推荐注入逻辑:**
    - 在修改 `UI.Recommendations` 队列时，插件会将原有的推荐内容备份在 `originalRecommendation` 字段中，以便在条件不再满足时恢复原始推荐。
    - 为推荐位添加了 `isMeleeIndicator` 或 `isHealingShamanSkill` 等自定义标记，用于识别该推荐是否由本插件产生。
- **外部依赖:**
    - `LibRangeCheck-2.0`: 用于精确的距离检测逻辑（例如判断 5 码近战范围）。

## 构建与运行

魔兽插件不需要编译过程。测试更改的方法如下：

1.  将 `HekiliHelper` 文件夹放置在魔兽世界的 `Interface\AddOns` 目录下。
2.  在游戏内使用 `/reload` 命令重新加载界面以应用 Lua 更改。
3.  必须确保同时启用了 `Hekili` 插件，因为本项目对其有强依赖。

## 关键文件说明

- `HekiliHelper.toc`: 插件元数据定义及文件加载顺序。
- `HekiliHelper.lua`: 插件主初始化逻辑及公共工具函数。
- `Modules/Options.lua`: 插件配置界面的定义。
- `Modules/MeleeTargetIndicator.lua`: 近战目标指示器的核心逻辑。
- `Modules/HealingShamanSkills.lua`: 萨满职业专用的治疗推荐逻辑。

## AI Agent 交互准则

在处理此项目时，请遵循以下原则：

1.  **严禁增加未要求的功能**：仅执行用户明确要求的任务，不要自行添加任何额外的功能或逻辑。
2.  **改进建议需确认**：如果你有更好的实现方案或改进建议，必须先提供**具体的技术方案**，并明确**征得用户同意**后方可执行。
3.  **Git 操作需确认**：在执行任何 `git` 相关命令（包括但不限于 commit, push, branch 等）之前，必须**告知用户具体操作内容并获得确认**。
4.  **保持风格一致**：修改代码时必须严格遵循项目中已有的代码风格、命名规范和 Ace3 框架的使用习惯。
