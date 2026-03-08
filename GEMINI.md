# HekiliHelper - Gemini 上下文 (Instructional Context)

HekiliHelper 是一个魔兽世界（怀旧服/WLK）插件，旨在增强 **Hekili** 技能循环辅助插件的功能。它为 Hekili 原生系统未涵盖的治疗职业逻辑、近战指示器以及特定职业（如死骑的疾病刷新）提供专门的支持。

## 项目概览

- **类型:** 魔兽世界插件 (Lua)
- **框架:** [Ace3](https://www.curseforge.com/wow/addons/ace3) (AceAddon, AceDB, AceConfig, AceEvent)。
- **核心机制:** 通过挂钩 (Hook) `Hekili.Update` 函数，将自定义的动作推荐注入到 `Hekili.DisplayPool` 的 Primary 队列中。
- **目标版本:** 魔兽世界怀旧服 (WLK/3.4.x)。

### 系统架构

1.  **入口文件 (`HekiliHelper.lua`):** 
    - 初始化 Ace3 插件对象和数据库存档 (`HekiliHelperDB`)。
    - 管理内置的调试系统（`/hhdebugwin` 窗口）。
    - 负责所有模块的顺序初始化，并使用 `pcall` 保护初始化链。
2.  **模块化设计 (`Modules/`):**
    - `Options.lua`: 使用 `AceConfig-3.0` 定义配置，并无缝集成到 Hekili 的选项菜单中。
    - `MeleeTargetIndicator.lua`: 核心功能之一。当玩家身边有敌人（5码内）但未攻击或目标超出范围时，在 Hekili 界面最前端插入“近战目标”提示。
    - `TTD.lua`: Time To Die 计算模块。通过采样单位血量变化，计算预计死亡时间，供其他逻辑（如 DK 传染、术士 DOT）使用。
    - `HealingShamanSkills.lua` / `HealingPriestSkills.lua`: 为治疗职业提供智能目标选择和基于血量/法强阈值的技能推荐。
    - `DeathKnightSkills.lua`: 专门处理 DK 的疾病扩散（传染）和刷新逻辑。
    - `UIModifier.lua`: 对 Hekili 的原生 UI 元素进行微调。
3.  **挂钩与注入逻辑:**
    - 使用 `HekiliHelper.HookUtils.Hook` 挂载在 `Hekili.Update` 之后运行。
    - 注入到 `UI.Recommendations[1]` 位，并备份原始推荐以便在条件不满足时恢复。

## 开发约定

- **全局对象:** 主插件对象存储在 `_G.HekiliHelper`。
- **配置访问:** 通过 `HekiliHelper.DB.profile` 访问持久化设置。
- **调试系统:** 
    - 游戏内命令: `/hhdebug` (切换调试状态), `/hhdebugwin` (显示调试窗口)。
    - 使用 `HekiliHelper:DebugPrint(msg)` 进行记录。
- **外部依赖:** 
    - `LibRangeCheck-2.0`: 用于精确的距离检测。
    - `Hekili`: 必须处于启用状态，本插件依赖其 UI 队列和 API。

## 构建与测试

- **环境:** 魔兽世界插件无需编译。
- **部署:** 将 `HekiliHelper` 文件夹放置在 `Interface\AddOns`。
- **测试:** 修改 Lua 文件后，在游戏内使用 `/reload` 命令重新加载。
- **验证:** 使用调试模式检查 `/hhdebugwin` 中的状态日志，确保 Hook 逻辑被正确触发。

## 关键文件说明

- `HekiliHelper.toc`: 插件清单，定义了文件加载顺序。
- `HekiliHelper.lua`: 插件核心，处理生命周期和公共工具。
- `Modules/MeleeTargetIndicator.lua`: 近战指示器实现。
- `Modules/Options.lua`: 配置界面定义。

## AI Agent 交互准则

1.  **保护初始化链**: 修改模块时，确保不破坏 `HekiliHelper.lua` 中的 `InitializeModules` 逻辑。
2.  **Hook 安全**: 优先使用 `HookUtils.Hook` 进行非侵入式挂钩。
3.  **状态恢复**: 在注入 `Recommendations` 队列时，务必正确保存和恢复 `originalRecommendation`，防止覆盖 Hekili 原生的推荐。
4.  **性能敏感**: `Hekili.Update` 每帧或极高频率运行，注入逻辑和距离检查必须高度优化，避免产生大量垃圾回收 (GC) 压力。
