-- Modules/HealingShamanSkills.lua
-- 治疗萨满技能插入模块
-- 在优先级队列中插入治疗萨满推荐技能
-- 针对WLK版本的治疗萨满，提供常用治疗技能的推荐框架

-- 获取HekiliHelper对象（这个文件在HekiliHelper.lua之后加载，所以对象应该已存在）
local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    -- 如果HekiliHelper还不存在，说明加载顺序有问题
    -- 这种情况下，我们延迟创建模块
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.HealingShamanSkills then
            HH.HealingShamanSkills = {}
        end
    end)
    return
end

-- 创建模块对象
if not HekiliHelper.HealingShamanSkills then
    HekiliHelper.HealingShamanSkills = {}
end

local Module = HekiliHelper.HealingShamanSkills

-- 模块初始化
function Module:Initialize()
    if not Hekili then
        HekiliHelper:Print("|cFFFF0000[HealingShaman]|r 错误: Hekili对象不存在")
        return false
    end
    
    if not Hekili.Update then
        HekiliHelper:Print("|cFFFF0000[HealingShaman]|r 错误: Hekili.Update函数不存在")
        return false
    end
    
    HekiliHelper:DebugPrint("|cFF00FF00[HealingShaman]|r 开始Hook Hekili.Update...")
    
    -- 关键发现：Hekili.Update是协程，在2070行设置UI.NewRecommendations = true
    -- 然后在2073行调用UI:SetThreadLocked(false)
    -- 问题：UI的OnUpdate在1091行检查NewRecommendations，但可能在我们插入之前就处理了
    -- 解决方案：在Hekili.Update中，在设置NewRecommendations之前就插入我们的技能
    
    -- Hook Hekili.Update函数，参考MeleeTargetIndicator的实现
    -- 关键：使用C_Timer.After延迟插入，确保在Hekili完成所有操作后再插入
    -- 这样可以避免与Hekili的推荐生成过程产生竞争
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        -- 在Hekili生成推荐之前，先保存我们的技能，防止被清除
        local savedSkills = {}
        if Hekili and Hekili.DisplayPool then
            for dispName, UI in pairs(Hekili.DisplayPool) do
                if UI and UI.Recommendations then
                    local Queue = UI.Recommendations
                    savedSkills[dispName] = {}
                    for i = 1, 4 do
                        if Queue[i] and Queue[i].isHealingShamanSkill then
                            -- 保存我们的技能
                            savedSkills[dispName][i] = {}
                            for k, v in pairs(Queue[i]) do
                                savedSkills[dispName][i][k] = v
                            end
                        end
                    end
                end
            end
        end
        
        -- 调用原函数生成推荐（这是协程，可能不会立即完成）
        local result = oldFunc(self, ...)
        
        -- 在所有推荐生成完成后，恢复我们的技能（如果被清除）并插入新技能
        -- 使用更短的延迟，减少与Hekili更新的竞争
        -- 参考MeleeTargetIndicator的实现，使用0.001秒延迟
        C_Timer.After(0.001, function()
            -- 先恢复被清除的技能
            if Hekili and Hekili.DisplayPool then
                for dispName, saved in pairs(savedSkills) do
                    local UI = Hekili.DisplayPool[dispName]
                    if UI and UI.Recommendations then
                        local Queue = UI.Recommendations
                        for i, savedSlot in pairs(saved) do
                            -- 如果我们的技能被清除了，恢复它
                            if not Queue[i] or not Queue[i].isHealingShamanSkill then
                                Queue[i] = {}
                                for k, v in pairs(savedSlot) do
                                    Queue[i][k] = v
                                end
                                -- 设置NewRecommendations，确保UI更新
                                UI.NewRecommendations = true
                                HekiliHelper:DebugPrint(string.format("|cFF00FFFF[HealingShaman]|r 恢复被清除的技能: %s (位置 %d)", savedSlot.actionName or "unknown", i))
                            end
                        end
                    end
                end
            end
            
            -- 然后插入新技能（这会更新已存在的技能或插入新技能）
            Module:InsertHealingSkills()
        end)
        
        return result
    end)
    
    if success then
        HekiliHelper:DebugPrint("|cFF00FF00[HealingShaman]|r 模块已初始化，Hook成功")
        return true
    else
        HekiliHelper:Print("|cFFFF0000[HealingShaman]|r Hook失败")
        return false
    end
end

-- ============================================
-- 技能定义列表
-- ============================================

-- WLK治疗萨满常用技能定义（不包括图腾）
-- 每个技能包含：actionName（Hekili中的key）、spellID、priority（优先级，越小越优先）、checkFunc（判断函数）、displayName（显示名称）
Module.SkillDefinitions = {
    {
        actionName = "stoneclaw_totem",
        spellID = 58582,
        priority = 8,
        checkFunc = function(self) return self:CheckStoneclawTotem() end,
        displayName = "石爪图腾"
    },
    {
        actionName = "water_shield",
        spellID = 57960,
        priority = 1,
        checkFunc = function(self) return self:CheckWaterShield() end,
        displayName = "水之护盾"
    },
    {
        actionName = "earthliving_weapon",
        spellID = 51994,
        priority = 2,
        checkFunc = function(self) return self:CheckEarthlivingWeapon() end,
        displayName = "大地生命武器"
    },
    {
        actionName = "earth_shield",
        spellID = 49284,
        priority = 3,
        checkFunc = function(self) return self:CheckEarthShield() end,
        displayName = "大地之盾"
    },
    {
        actionName = "riptide",
        spellID = 61295,
        priority = 4,
        checkFunc = function(self) return self:CheckRiptide() end,
        displayName = "激流"
    },
    {
        actionName = "tide_force",
        spellID = 55198,
        priority = 4.5,
        checkFunc = function(self) return self:CheckTideForce() end,
        displayName = "潮汐之力"
    },
    {
        actionName = "chain_heal",
        spellID = 49273,
        priority = 6,
        checkFunc = function(self) return self:CheckChainHeal() end,
        displayName = "治疗链"
    },
    {
        actionName = "healing_wave",
        spellID = 49273,
        priority = 5,
        checkFunc = function(self) return self:CheckHealingWave() end,
        displayName = "治疗波"
    },
    {
        actionName = "lesser_healing_wave",
        spellID = 49276, -- 最高等级
        priority = 7,
        checkFunc = function(self) return self:CheckLesserHealingWave() end,
        displayName = "次级治疗波"
    },
    {
        actionName = "purge",
        spellID = 370,
        priority = 9,
        checkFunc = function(self) return self:CheckPurge() end,
        displayName = "净化术"
    },
    {
        actionName = "dispel_magic",
        spellID = 370,
        priority = 10,
        checkFunc = function(self) return self:CheckDispelMagic() end,
        displayName = "驱散魔法"
    },
    {
        actionName = "natures_swiftness",
        spellID = 16188,
        priority = 11,
        checkFunc = function(self) return self:CheckNaturesSwiftness() end,
        displayName = "自然迅捷"
    },
    {
        actionName = "cure_disease",
        spellID = 2870,
        priority = 12,
        checkFunc = function(self) return self:CheckCureDisease() end,
        displayName = "祛病术"
    },
    {
        actionName = "cure_poison",
        spellID = 526,
        priority = 13,
        checkFunc = function(self) return self:CheckCurePoison() end,
        displayName = "解毒术"
    },
    {
        actionName = "wind_shear",
        spellID = 57994,
        priority = 14,
        checkFunc = function(self) return self:CheckWindShear() end,
        displayName = "风剪"
    },
    {
        actionName = "mana_tide_totem",
        spellID = 16190,
        priority = 15,
        checkFunc = function(self) return self:CheckManaTideTotem() end,
        displayName = "法力之潮图腾"
    },
}

-- ============================================
-- 技能判断函数占位符
-- ============================================

-- 治疗链判断
function Module:CheckChainHeal()
    -- 检查模块是否启用
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        return false, nil
    end
    
    -- 检查鼠标悬停目标或当前选中目标
    local targetUnit = nil
    
    -- 优先检查鼠标悬停目标
    if self:IsValidHealingTarget("mouseover") then
        targetUnit = "mouseover"
    -- 其次检查当前选中目标
    elseif self:IsValidHealingTarget("target") then
        targetUnit = "target"
    -- 兜底：检查焦点目标
    elseif self:IsValidHealingTarget("focus") then
        targetUnit = "focus"
    end
    
    -- 如果没有有效的目标，返回false
    if not targetUnit then
        return false, nil
    end
    
    -- 检查目标是否是团队或小队中的成员
    local isInGroup = false
    if IsInGroup() then
        if IsInRaid() then
            -- 检查是否是团队成员
            for i = 1, 40 do
                local unit = "raid" .. i
                if UnitExists(unit) and UnitIsUnit(unit, targetUnit) then
                    isInGroup = true
                    break
                end
            end
        else
            -- 检查是否是小队成员
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) and UnitIsUnit(unit, targetUnit) then
                    isInGroup = true
                    break
                end
            end
            -- 检查是否是玩家自己
            if UnitIsUnit("player", targetUnit) then
                isInGroup = true
            end
        end
    else
        -- 单人模式，检查是否是玩家自己
        if UnitIsUnit("player", targetUnit) then
            isInGroup = true
        end
    end
    
    -- 如果不是团队成员，返回false
    if not isInGroup then
        return false, nil
    end
    
    -- 读取配置中的治疗链触发阈值
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    local threshold = (db and db.healingShaman and db.healingShaman.chainHealThreshold) or 90
    
    -- 检查目标剩余血量是否低于阈值
    local targetHealthPercent = self:GetUnitHealthPercent(targetUnit)
    if targetHealthPercent > threshold then
        return false, nil
    end
    
    -- 获取目标的小队编号
    local targetGroup, targetPosition = self:GetGroupPosition(targetUnit)
    
    -- 判断1：检查同小队的其他成员是否也有损失10%以上血量的
    if targetGroup and targetPosition then
        local injuredInSameGroup = 0
        
                -- 遍历所有团队成员
        if IsInRaid() then
            for i = 1, 40 do
                local unit = "raid" .. i
                if self:IsValidHealingTarget(unit) and UnitInPhase(unit) then
                    local group, position = self:GetGroupPosition(unit)
                    if group == targetGroup and not UnitIsUnit(unit, targetUnit) then
                        local healthPercent = self:GetUnitHealthPercent(unit)
                        if healthPercent <= threshold then
                            injuredInSameGroup = injuredInSameGroup + 1
                        end
                    end
                end
            end
        elseif IsInGroup() then
            -- 小队模式
            if UnitIsUnit("player", targetUnit) then
                -- 目标是玩家，检查其他小队成员
                for i = 1, 4 do
                    local unit = "party" .. i
                    if self:IsValidHealingTarget(unit) and UnitInPhase(unit) then
                        local healthPercent = self:GetUnitHealthPercent(unit)
                        if healthPercent <= threshold then
                            injuredInSameGroup = injuredInSameGroup + 1
                        end
                    end
                end
            else
                -- 目标是其他小队成员，检查玩家和其他成员
                local playerHealth = self:GetUnitHealthPercent("player")
                if playerHealth <= threshold then
                    injuredInSameGroup = injuredInSameGroup + 1
                end
                for i = 1, 4 do
                    local unit = "party" .. i
                    if self:IsValidHealingTarget(unit) and not UnitIsUnit(unit, targetUnit) and UnitInPhase(unit) then
                        local healthPercent = self:GetUnitHealthPercent(unit)
                        if healthPercent <= threshold then
                            injuredInSameGroup = injuredInSameGroup + 1
                        end
                    end
                end
            end
        end
        
        -- 如果同小队有受伤的成员，返回true
        if injuredInSameGroup > 0 then
            return true, targetUnit
        end
    end
    
    -- 判断2：检查同职业类型（近战或远程）是否有超过一个损失10%以上血量的
    local targetClassType = self:GetClassType(targetUnit)
    if targetClassType then
        local injuredSameType = 0
        
                -- 遍历所有团队成员
        if IsInRaid() then
            for i = 1, 40 do
                local unit = "raid" .. i
                if self:IsValidHealingTarget(unit) and UnitInPhase(unit) then
                    local classType = self:GetClassType(unit)
                    if classType == targetClassType then
                        local healthPercent = self:GetUnitHealthPercent(unit)
                        if healthPercent <= threshold then
                            injuredSameType = injuredSameType + 1
                        end
                    end
                end
            end
        elseif IsInGroup() then
            -- 小队模式
            -- 检查玩家
            local playerClassType = self:GetClassType("player")
            if playerClassType == targetClassType then
                local playerHealth = self:GetUnitHealthPercent("player")
                if playerHealth <= threshold then
                    injuredSameType = injuredSameType + 1
                end
            end
            -- 检查其他小队成员
            for i = 1, 4 do
                local unit = "party" .. i
                if self:IsValidHealingTarget(unit) and UnitInPhase(unit) then
                    local classType = self:GetClassType(unit)
                    if classType == targetClassType then
                        local healthPercent = self:GetUnitHealthPercent(unit)
                        if healthPercent <= threshold then
                            injuredSameType = injuredSameType + 1
                        end
                    end
                end
            end
        end
        
        -- 如果同职业类型有超过一个损失10%以上血量的，返回true
        if injuredSameType > 1 then
            return true, targetUnit
        end
    end
    
    return false, nil
end

-- 石爪图腾判断 (逻辑更新：没有土图腾时触发)
function Module:CheckStoneclawTotem()
    -- 1. 基础检查：模块启用
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        HekiliHelper:DebugPrint("|cFFFF0000[Stoneclaw]|r 模块禁用")
        return false, nil
    end

    -- 新增：检查是否启用了石爪图腾雕文判断
    if db.healingShaman.enableStoneclawGlyph ~= true then
        return false, nil
    end

    local stoneclawName = GetSpellInfo(5730) -- 石爪图腾 (基础)
    local glyphSpellID = 55438 -- 石爪图腾雕文
    local expectedGlyphName = GetSpellInfo(glyphSpellID)

    -- 2. 核心前提：必须装备了石爪图腾雕文
    local hasGlyph = false
    local currentSpec = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
    
    for i = 1, 6 do
        -- WotLK API: enabled, glyphType, glyphTooltipIndex, glyphSpellID, icon
        local enabled, _, _, glyphSpell, _ = GetGlyphSocketInfo(i, currentSpec)
        if enabled and glyphSpell then
            local currentGlyphName = GetSpellInfo(glyphSpell)
            if HekiliHelper.DebugEnabled then
                HekiliHelper:DebugPrint(string.format("|cFFFF0000[Stoneclaw]|r 检查插槽 %d: ID %s, 名称 %s", i, tostring(glyphSpell), tostring(currentGlyphName)))
            end
            if glyphSpell == glyphSpellID or glyphSpell == 55439 or glyphSpell == 43388 or glyphSpell == 63298 or (expectedGlyphName and currentGlyphName == expectedGlyphName) then
                hasGlyph = true
                break
            end
        end
    end
    
    if not hasGlyph then 
        HekiliHelper:DebugPrint("|cFFFF0000[Stoneclaw]|r 未装备石爪图腾雕文 (检查了6个插槽)")
        return false, nil 
    end

    -- 3. 战斗状态检查
    if not UnitAffectingCombat("player") then
        HekiliHelper:DebugPrint("|cFFFF0000[Stoneclaw]|r 不在战斗中")
        return false, nil
    end

    -- 4. 技能可用性检查
    -- 使用名称检查冷却，兼容不同等级
    local start, duration, enabled = GetSpellCooldown(stoneclawName)
    local isReady = not start or start == 0 or ((start + duration) - GetTime() <= 0)
    
    if not isReady then 
        HekiliHelper:DebugPrint("|cFFFF0000[Stoneclaw]|r 技能冷却中")
        return false, nil 
    end

    local usable, noMana = IsUsableSpell(stoneclawName)
    if not usable or noMana then
        HekiliHelper:DebugPrint("|cFFFF0000[Stoneclaw]|r 技能不可用 (缺蓝或缺少图腾)")
        return false, nil
    end

    -- 5. 触发条件：检查当前是否已有土图腾
    -- 打印当前所有图腾状态以供调试
    if HekiliHelper.DebugEnabled then
        local totems = {}
        for i = 1, 4 do
            local _, name, startTime, duration = GetTotemInfo(i)
            if name and name ~= "" and duration > 0 then
                local timeLeft = (startTime + duration) - GetTime()
                if timeLeft > 0 then
                    table.insert(totems, string.format("[%d]%s(%.1fs)", i, name, timeLeft))
                end
            end
        end
        HekiliHelper:DebugPrint(string.format("|cFFFF0000[Stoneclaw]|r 当前活动图腾: %s", #totems > 0 and table.concat(totems, ", ") or "无"))
    end

    if GetTotemInfo then
        -- 1=火, 2=土, 3=水, 4=风
        local haveTotem, totemName, startTime, duration = GetTotemInfo(2) 
        -- 必须检查 duration 和剩余时间，因为有时 API 会返回已消失图腾的残余数据
        if haveTotem and totemName and totemName ~= "" and duration > 0 then
            local timeLeft = (startTime + duration) - GetTime()
            if timeLeft > 0 then
                HekiliHelper:DebugPrint(string.format("|cFFFF0000[Stoneclaw]|r 已存在土图腾: %s (剩余 %.1fs)", totemName, timeLeft))
                return false, nil
            end
        end
    end

    -- 所有条件满足，触发推荐
    HekiliHelper:DebugPrint("|cFF00FF00[Stoneclaw]|r 触发推荐 (无土图腾、战斗中、雕文存在)")
    return true, "player"
end

-- 治疗波判断
function Module:CheckHealingWave()
    -- 检查模块是否启用
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        return false, nil
    end
    
    if db.healingShaman.enableHealingWave == false then
        return false, nil
    end

    -- 检查鼠标悬停目标或当前选中目标
    local targetUnit = nil
    
    -- 优先检查鼠标悬停目标
    if self:IsValidHealingTarget("mouseover") then
        targetUnit = "mouseover"
    -- 其次检查当前选中目标
    elseif self:IsValidHealingTarget("target") then
        targetUnit = "target"
    -- 兜底：检查焦点目标
    elseif self:IsValidHealingTarget("focus") then
        targetUnit = "focus"
    end
    
    -- 如果没有有效的目标，返回false
    if not targetUnit then
        return false, nil
    end
    
    -- 读取配置中的治疗波触发阈值
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    local threshold = (db and db.healingShaman and db.healingShaman.healingWaveThreshold) or 30
    
    -- 检查目标剩余血量是否低于阈值
    local targetHealthPercent = self:GetUnitHealthPercent(targetUnit)
    if targetHealthPercent <= threshold then
        return true, targetUnit
    end
    
    return false, nil
end

-- 次级治疗波判断
function Module:CheckLesserHealingWave()
    -- 检查模块是否启用
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        return false, nil
    end
    
    if db.healingShaman.enableLesserHealingWave == false then
        return false, nil
    end

    -- 检查鼠标悬停目标或当前选中目标
    local targetUnit = nil
    
    -- 优先检查鼠标悬停目标
    if self:IsValidHealingTarget("mouseover") then
        targetUnit = "mouseover"
    -- 其次检查当前选中目标
    elseif self:IsValidHealingTarget("target") then
        targetUnit = "target"
    -- 兜底：检查焦点目标
    elseif self:IsValidHealingTarget("focus") then
        targetUnit = "focus"
    end
    
    -- 如果没有有效的目标，返回false
    if not targetUnit then
        return false, nil
    end
    
    -- 读取配置中的次级治疗波触发阈值
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    local threshold = (db and db.healingShaman and db.healingShaman.lesserHealingWaveThreshold) or 90
    
    -- 检查目标剩余血量是否低于阈值
    local targetHealthPercent = self:GetUnitHealthPercent(targetUnit)
    if targetHealthPercent > threshold then
        return false, nil
    end
    
    -- 只要目标剩余血量低于阈值就返回true
    return true, targetUnit
end

-- 潮汐之力判断
-- 潮汐之力判断
function Module:CheckTideForce()
    -- 1. 基础检查：模块启用、是否学习、是否在冷却中
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        return false, nil
    end
    
    local tideForceSpellID = 55198
    
    -- 增加：冷却检查（如果正在冷却则直接退出）
    if not self:IsSpellReady(tideForceSpellID) then
        return false, nil
    end

    -- 检查是否学习了技能
    if IsSpellKnown and not IsSpellKnown(tideForceSpellID) then
        return false, nil
    end
    
    -- 2. 阈值与环境检查
    local threshold = (db and db.healingShaman and db.healingShaman.tideForceThreshold) or 50
    
    if IsInRaid() then
        -- 团队状态：1/3以上成员生命值低于阈值
        local totalMembers = 0
        local injuredMembers = 0
        
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) and self:IsValidHealingTarget(unit) and UnitInPhase(unit) then
                totalMembers = totalMembers + 1
                if self:GetUnitHealthPercent(unit) < threshold then
                    injuredMembers = injuredMembers + 1
                end
            end
        end
        
        if totalMembers > 0 and injuredMembers >= math.ceil(totalMembers / 3) then
            return true, "player"
        end
    elseif IsInGroup() then
        -- 小队状态
        local totalMembers = 0
        local injuredMembers = 0
        
        -- 统计玩家及小队成员
        local groupUnits = { "player", "party1", "party2", "party3", "party4" }
        for _, unit in ipairs(groupUnits) do
            if self:IsValidHealingTarget(unit) and UnitInPhase(unit) then
                totalMembers = totalMembers + 1
                if self:GetUnitHealthPercent(unit) < threshold then
                    injuredMembers = injuredMembers + 1
                end
            end
        end
        
        if totalMembers > 0 and injuredMembers >= (math.floor(totalMembers / 2) + 1) then
            return true, "player"
        end
    end
    
    return false, nil
end

-- 激流判断
function Module:CheckRiptide()
    -- 检查模块是否启用
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        return false, nil
    end
    
    local riptideSpellID = 61295
    if IsSpellKnown and not IsSpellKnown(riptideSpellID) then
        return false, nil
    end

    -- 检查鼠标悬停目标或当前选中目标
    local targetUnit = nil
    
    -- 优先检查鼠标悬停目标
    if self:IsValidHealingTarget("mouseover") then
        targetUnit = "mouseover"
    -- 其次检查当前选中目标
    elseif self:IsValidHealingTarget("target") then
        targetUnit = "target"
    -- 兜底：检查焦点目标
    elseif self:IsValidHealingTarget("focus") then
        targetUnit = "focus"
    end
    
    -- 如果没有有效的目标，返回false
    if not targetUnit then
        return false, nil
    end
    
    -- 读取配置中的激流触发阈值
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    local threshold = (db and db.healingShaman and db.healingShaman.riptideThreshold) or 99
    
    -- 检查目标剩余血量是否低于阈值
    local targetHealthPercent = self:GetUnitHealthPercent(targetUnit)
    if targetHealthPercent > threshold then
        return false, nil
    end
    
    -- 检查激流是否冷却完毕
    local riptideSpellID = 61295
    if not self:IsSpellReady(riptideSpellID) then
        return false, nil
    end
    
    -- 检查技能是否可用（包括蓝量检查）
    -- IsUsableSpell返回两个值：usable（是否可用）和nomana（是否因法力不足而不可用）
    if IsUsableSpell then
        local isUsable, notEnoughMana = IsUsableSpell(riptideSpellID)
        -- 如果技能不可用，或者因法力不足而不可用，返回false
        if not isUsable or notEnoughMana then
            return false, nil
        end
    else
        -- 回退方案：如果IsUsableSpell不可用，检查技能是否在技能书中
        if IsSpellKnown then
            if not IsSpellKnown(riptideSpellID) then
                return false, nil
            end
        end
    end
    
    -- 所有条件满足，返回true
    return true, targetUnit
end

-- 大地之盾判断
function Module:CheckEarthShield()
    -- 检查模块是否启用
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        return false, nil
    end
    
    local earthShieldSpellID = 49284
    if IsSpellKnown and not IsSpellKnown(earthShieldSpellID) then
        return false, nil
    end

    -- 只有当存在焦点目标时才推荐使用大地之盾
    if not UnitExists("focus") then
        return false, nil
    end
    
    -- 检查焦点目标是否是有效的治疗目标（友方、存活、在视野范围内）
    if not self:IsValidHealingTarget("focus") then
        return false, nil
    end
    
    -- 检查焦点目标是否有大地之盾buff
    local hasEarthShield = self:HasBuff("focus", "大地之盾") or self:HasBuff("focus", "Earth Shield")
    
    -- 如果没有大地之盾，返回true
    if not hasEarthShield then
        return true, "focus"
    end
    
    return false, nil
end

-- 法力之潮图腾判断
function Module:CheckManaTideTotem()
    -- 检查模块是否启用
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        return false, nil
    end
    
    local manaTideTotemSpellID = 16190
    
    -- 检查是否学习了技能
    if IsSpellKnown and not IsSpellKnown(manaTideTotemSpellID) then
        return false, nil
    end
    
    -- 检查自身法力值是否低于50%
    local currentMana = UnitPower("player", 0) -- 0表示法力值
    local maxMana = UnitPowerMax("player", 0)
    if maxMana <= 0 then
        return false, nil
    end
    local manaPercent = currentMana / maxMana
    if manaPercent >= 0.5 then
        return false, nil
    end
    
    -- 检查是否已有法力之潮图腾（检查水图腾槽，slot 3）
    if GetTotemInfo then
        local haveTotem, totemName, startTime, duration = GetTotemInfo(3)
        if haveTotem and totemName then
            -- 检查图腾名称是否包含"法力之潮"或"Mana Tide"
            if string.find(totemName, "法力之潮") or string.find(totemName, "Mana Tide") then
                return false, nil
            end
        end
    end
    
    -- 检查40码范围内是否有战斗中的boss
    local RC = LibStub and LibStub("LibRangeCheck-2.0")
    local hasBossInRange = false
    
    -- 检查boss单位（boss1-5）
    for i = 1, 5 do
        local unit = "boss" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit) then
            local classification = UnitClassification(unit)
            -- 检查是否为boss级别（worldboss, rareelite, elite）
            if (classification == "worldboss" or classification == "rareelite" or classification == "elite") then
                -- 检查是否在战斗中（需要boss和玩家都在战斗中）
                if UnitAffectingCombat and UnitAffectingCombat(unit) and UnitAffectingCombat("player") then
                    -- 检查玩家是否与该boss在战斗中（通过检查threat状态）
                    local isInCombat = false
                    if UnitThreatSituation then
                        -- 检查玩家对该boss的威胁值情况，如果返回非nil且>=0，说明在战斗中
                        local threatSituation = UnitThreatSituation("player", unit)
                        if threatSituation and threatSituation >= 0 then
                            isInCombat = true
                        end
                    else
                        -- 如果没有UnitThreatSituation API，只检查是否都在战斗中
                        isInCombat = true
                    end
                    
                    if isInCombat then
                        -- 检查距离（40码）
                        if RC then
                            local minRange, maxRange = RC:GetRange(unit)
                            if maxRange and maxRange <= 40 then
                                hasBossInRange = true
                                break
                            end
                        else
                            -- 如果没有LibRangeCheck，使用CheckInteractDistance作为替代
                            -- CheckInteractDistance的第二个参数：1=交易(约11码), 2=观察(约28码), 3=决斗(约9码), 4=跟随
                            -- 我们检查28码（观察距离），如果在这个范围内，应该也在40码内
                            if CheckInteractDistance and CheckInteractDistance(unit, 2) then
                                hasBossInRange = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- 如果还没有找到，检查nameplate单位
    if not hasBossInRange and RC and Hekili and Hekili.npGUIDs then
        for unit, guid in pairs(Hekili.npGUIDs) do
            if unit and type(unit) == "string" and UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit) then
                local classification = UnitClassification(unit)
                if (classification == "worldboss" or classification == "rareelite" or classification == "elite") then
                    -- 检查是否在战斗中（需要boss和玩家都在战斗中）
                    if UnitAffectingCombat and UnitAffectingCombat(unit) and UnitAffectingCombat("player") then
                        -- 检查玩家是否与该boss在战斗中
                        local isInCombat = false
                        if UnitThreatSituation then
                            local threatSituation = UnitThreatSituation("player", unit)
                            if threatSituation and threatSituation >= 0 then
                                isInCombat = true
                            end
                        else
                            isInCombat = true
                        end
                        
                        if isInCombat then
                            local minRange, maxRange = RC:GetRange(unit)
                            if maxRange and maxRange <= 40 then
                                hasBossInRange = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- 如果找到了战斗中的boss，返回true
    if hasBossInRange then
        return true, "player"
    end
    
    return false, nil
end

-- 净化术判断
function Module:CheckPurge()
    -- TODO: 添加判断逻辑
    return false, nil
end

-- 驱散魔法判断
function Module:CheckDispelMagic()
    -- TODO: 添加判断逻辑
    return false, nil
end

-- 自然迅捷判断
function Module:CheckNaturesSwiftness()
    -- TODO: 添加判断逻辑
    return false, nil
end

-- 水之护盾判断
function Module:CheckWaterShield()
    -- 检查模块是否启用
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        return false, nil
    end
    
    -- 检查玩家是否有水之护盾buff
    -- 水之护盾的spellID是57960
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if not name then
            break
        end
        
        -- 检查spellID是否为57960（水之护盾的技能ID）
        if spellId == 57960 then
            -- 找到了水之护盾buff，返回false
            return false, nil
        end
        
        -- 检查buff名称是否包含"水之护盾"（支持中文）或"Water Shield"（支持英文）
        if name and (string.find(name, "水之护盾") or string.find(name, "Water Shield")) then
            -- 找到了水之护盾buff，返回false
            return false, nil
        end
    end
    
    -- 没有找到水之护盾buff，返回true
    return true, "player"
end

-- 祛病术判断
function Module:CheckCureDisease()
    -- TODO: 添加判断逻辑
    return false, nil
end

-- 解毒术判断
function Module:CheckCurePoison()
    -- TODO: 添加判断逻辑
    return false, nil
end

-- 风剪判断
function Module:CheckWindShear()
    -- TODO: 添加判断逻辑
    return false, nil
end


function Module:CheckEarthlivingWeapon()
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        return false, nil
    end
    
    local earthlivingID = 3350
    local info = { GetWeaponEnchantInfo() }
    

    local hasMain, mainID = info[1], info[4]
    local hasOff, offID = info[5], info[8]

    if not hasMain or mainID ~= earthlivingID then
        return true, "player"
    end

    local offhandID = GetInventoryItemID("player", 17)
    if offhandID then

        local isWeapon = IsSecondarySkillWeapon and IsSecondarySkillWeapon()
        if not hasOff or offID ~= earthlivingID then
            local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(offhandID)
            if itemEquipLoc ~= "INVTYPE_SHIELD" and itemEquipLoc ~= "INVTYPE_HOLDABLE" then
                return true, "player"
            end
        end
    end
    
    return false, nil
end

-- ============================================
-- 辅助函数
-- ============================================

-- 获取友方单位列表（用于治疗目标选择）
function Module:GetFriendlyUnits()
    local units = {}
    
    -- 添加玩家自己
    table.insert(units, "player")
    
    -- 添加小队成员
    if IsInGroup() then
        if IsInRaid() then
            -- 团队模式
            for i = 1, 40 do
                local unit = "raid" .. i
                if UnitExists(unit) then
                    table.insert(units, unit)
                end
            end
        else
            -- 小队模式
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) then
                    table.insert(units, unit)
                end
            end
        end
    end
    
    -- 添加目标（如果是友方）
    if UnitExists("target") and UnitIsFriend("player", "target") then
        table.insert(units, "target")
    end
    
    -- 添加焦点（如果是友方）
    if UnitExists("focus") and UnitIsFriend("player", "focus") then
        table.insert(units, "focus")
    end
    
    return units
end

-- 检查目标是否是有效的治疗目标（友方、存活、在视野范围内）
function Module:IsValidHealingTarget(unit)
    if not unit then
        return false
    end
    
    -- 检查目标是否存在
    if not UnitExists(unit) then
        return false
    end
    
    -- 检查目标是否是友方
    if not UnitIsFriend("player", unit) then
        return false
    end
    
    -- 检查目标是否死亡
    if UnitIsDead(unit) then
        return false
    end
    
    -- 检查目标是否在视野范围内（可见）
    if not UnitIsVisible(unit) then
        return false
    end
    
    if not UnitCanCooperate("player", unit) then return false end

    return true
end

-- 获取单位血量百分比
function Module:GetUnitHealthPercent(unit)
    if not UnitExists(unit) then
        return 100
    end
    
    local health = UnitHealth(unit)
    local maxHealth = UnitHealthMax(unit)
    
    if maxHealth == 0 then
        return 100
    end
    
    return (health / maxHealth) * 100
end

-- 获取单位的小队编号（格式：小队号-位置号，如1-1, 1-2, 2-1等）
-- 返回：groupIndex, positionIndex 或 nil, nil
function Module:GetGroupPosition(unit)
    if not UnitExists(unit) then
        return nil, nil
    end
    
    -- 检查是否是玩家自己
    if UnitIsUnit("player", unit) then
        if IsInGroup() then
            if IsInRaid() then
                -- 团队模式：获取玩家的小队和位置
                local name = UnitName("player")
                for i = 1, 40 do
                    local raidUnit = "raid" .. i
                    if UnitExists(raidUnit) and UnitName(raidUnit) == name then
                        local _, _, subgroup = GetRaidRosterInfo(i)
                        if subgroup then
                            return subgroup, i
                        end
                    end
                end
            else
                -- 小队模式：玩家是队长，在小队1
                return 1, 1
            end
        else
            -- 单人模式
            return 1, 1
        end
    end
    
    -- 检查是否是团队成员
    if IsInRaid() then
        for i = 1, 40 do
            local raidUnit = "raid" .. i
            if UnitExists(raidUnit) and UnitIsUnit(raidUnit, unit) then
                local _, _, subgroup = GetRaidRosterInfo(i)
                if subgroup then
                    return subgroup, i
                end
            end
        end
    elseif IsInGroup() then
        -- 小队模式
        if UnitIsUnit("player", unit) then
            return 1, 1
        end
        for i = 1, 4 do
            local partyUnit = "party" .. i
            if UnitExists(partyUnit) and UnitIsUnit(partyUnit, unit) then
                return 1, i + 1  -- 小队模式只有一个小队，位置从2开始（1是玩家）
            end
        end
    end
    
    return nil, nil
end

-- 判断职业类型（近战或远程）
-- 返回："melee" 或 "ranged" 或 nil
function Module:GetClassType(unit)
    if not UnitExists(unit) then
        return nil
    end
    
    local class = UnitClassBase(unit)
    if not class then
        return nil
    end
    
    -- 近战职业
    local meleeClasses = {
        WARRIOR = true,
        ROGUE = true,
        DEATHKNIGHT = true,
        PALADIN = true,  -- 虽然可以治疗，但通常是近战
    }
    
    -- 远程职业
    local rangedClasses = {
        HUNTER = true,
        MAGE = true,
        WARLOCK = true,
        PRIEST = true,
        DRUID = true,  -- 虽然可以近战，但通常作为远程治疗
        SHAMAN = true,  -- 虽然可以近战，但通常作为远程治疗
    }
    
    if meleeClasses[class] then
        return "melee"
    elseif rangedClasses[class] then
        return "ranged"
    end
    
    return nil
end

-- 检查单位是否有特定debuff
function Module:HasDebuff(unit, debuffName)
    if not UnitExists(unit) then
        return false
    end
    
    -- 检查最多40个debuff
    for i = 1, 40 do
        local name, _, _, debuffType = UnitDebuff(unit, i)
        if not name then
            break
        end
        if name == debuffName then
            return true
        end
    end
    
    return false
end

-- 检查单位是否有特定buff
function Module:HasBuff(unit, buffName)
    if not UnitExists(unit) then
        return false
    end
    
    -- 检查最多40个buff
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitBuff(unit, i)
        if not name then
            break
        end
        -- 检查名称或spellID（大地之盾的spellID是49284）
        if name == buffName or spellId == 49284 then
            return true
        end
    end
    
    return false
end

-- 检查技能是否可用
function Module:IsSpellReady(spellID)
    local start, duration = GetSpellCooldown(spellID)
    if not start or start == 0 then
        return true
    end
    
    local remaining = (start + duration) - GetTime()
    return remaining <= 0
end

-- 从Hekili获取技能信息
function Module:GetSkillFromHekili(actionName)
    if not Hekili or not Hekili.Class or not Hekili.Class.abilities then
        return nil
    end
    
    return Hekili.Class.abilities[actionName]
end

-- ============================================
-- 主插入函数
-- ============================================

-- 插入治疗技能
function Module:InsertHealingSkills()
    if not Hekili then
        return
    end
    
    -- 检查治疗萨满模块是否启用
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingShaman or db.healingShaman.enabled == false then
        return
    end
    
    -- 使用Hekili.DisplayPool访问displays对象
    local displays = Hekili.DisplayPool
    if not displays then
        return
    end
    
    -- 检查是否有激活的显示
    local activeCount = 0
    for dispName, UI in pairs(displays) do
        if UI and UI.Active and UI.alpha > 0 then
            activeCount = activeCount + 1
        end
    end
    
    if activeCount == 0 then
        return
    end
    
    -- 遍历所有激活的显示
    local processedCount = 0
    for dispName, UI in pairs(displays) do
        if UI and UI.Active and UI.alpha > 0 then
            processedCount = processedCount + 1
            self:InsertSkillForDisplay(dispName, UI)
        end
    end
    
    if processedCount > 0 then
        HekiliHelper:DebugPrint(string.format("|cFF00FFFF[HealingShaman]|r 处理了 %d 个激活的显示", processedCount))
    end
end

-- 为特定显示插入技能
function Module:InsertSkillForDisplay(dispName, UI)
    -- 只对Primary和AOE显示插入技能
    if dispName ~= "Primary" and dispName ~= "AOE" then
        return
    end
    
    if not UI or not UI.Recommendations then
        return
    end
    
    local Queue = UI.Recommendations
    
    -- 第一步：收集所有符合条件的技能
    local skillsToInsert = {}
    local skillsToInsertMap = {}  -- 用于快速查找
    for _, skillDef in ipairs(self.SkillDefinitions) do
        local shouldInsert, targetUnit = skillDef.checkFunc(self)
        
        if shouldInsert then
            table.insert(skillsToInsert, {skillDef = skillDef, targetUnit = targetUnit})
            skillsToInsertMap[skillDef.actionName] = true
        end
    end
    
    -- 第二步：检查队列中已有的技能，如果条件不再满足，移除它们
    -- 参考MeleeTargetIndicator的实现，智能移除不再需要的技能
    for i = 1, 4 do
        if Queue[i] and Queue[i].isHealingShamanSkill then
            local actionName = Queue[i].actionName
            -- 如果这个技能不再需要显示，移除它
            if not skillsToInsertMap[actionName] then
                -- 找到对应的skillDef，再次检查（确保条件真的不满足）
                local skillDef = nil
                for _, def in ipairs(self.SkillDefinitions) do
                    if def.actionName == actionName then
                        skillDef = def
                        break
                    end
                end
                
                if skillDef then
                    local shouldInsert, _ = skillDef.checkFunc(self)
                    if not shouldInsert then
                        -- 条件确实不满足，移除技能
                        self:RemoveSkillFromQueue(Queue, UI, i)
                    end
                else
                    -- 找不到skillDef，直接移除
                    self:RemoveSkillFromQueue(Queue, UI, i)
                end
            end
        end
    end
    
    -- 第三步：压缩队列，移除空位
    -- 当位置1的技能被移除后，位置2的技能应该立即移动到位置1
    -- 遍历队列，找到第一个空位，然后将后面的技能前移
    local needsCompression = false
    for i = 1, 3 do
        -- 如果当前位置为空或不是我们的技能，检查后面的位置
        local isEmpty = not Queue[i] or (not Queue[i].isHealingShamanSkill and (not Queue[i].actionName or Queue[i].actionName == ""))
        if isEmpty then
            -- 找到后面第一个有效的技能（我们的技能或Hekili的推荐）
            for j = i + 1, 4 do
                if Queue[j] and Queue[j].actionName and Queue[j].actionName ~= "" then
                    -- 移动技能到位置i
                    Queue[i] = Queue[i] or {}
                    -- 先清除位置i的所有属性
                    for k, v in pairs(Queue[i]) do
                        Queue[i][k] = nil
                    end
                    -- 复制位置j的所有属性到位置i
                    for k, v in pairs(Queue[j]) do
                        Queue[i][k] = v
                    end
                    -- 更新index
                    Queue[i].index = i
                    -- 清除原位置
                    Queue[j] = {}
                    needsCompression = true
                    HekiliHelper:DebugPrint(string.format("|cFF00FFFF[HealingShaman]|r 压缩队列：将位置 %d 的技能移动到位置 %d", j, i))
                    break
                end
            end
        end
    end
    
    -- 如果进行了压缩，触发UI更新
    if needsCompression then
        UI.NewRecommendations = true
    end
    
    -- 第四步：按优先级插入所有符合条件的技能
    -- 由于SkillDefinitions已经按优先级排序，直接按顺序插入即可
    -- 每个技能插入到对应的位置（priority 1 -> 位置1, priority 2 -> 位置2, 等等）
    for idx, skillData in ipairs(skillsToInsert) do
        -- 检查技能是否已经在队列中
        local alreadyInQueue = false
        local existingSlot = nil
        for i = 1, 4 do
            if Queue[i] and Queue[i].actionName == skillData.skillDef.actionName and Queue[i].isHealingShamanSkill then
                alreadyInQueue = true
                existingSlot = i
                break
            end
        end
        
        -- 确定插入位置：找到第一个空位或应该插入的位置
        local insertPos = idx
        -- 如果目标位置已有我们的技能且正确，只需要更新属性
        if alreadyInQueue and existingSlot == insertPos then
            -- 技能已在正确位置，只需要更新一些可能变化的属性
            local slot = Queue[insertPos]
            local ability = self:GetSkillFromHekili(skillData.skillDef.actionName)
            if ability then
                slot.texture = ability.texture
                slot.actionID = skillData.skillDef.spellID
            end
        else
            -- 如果目标位置被占用，检查是否可以前移
            if Queue[insertPos] and Queue[insertPos].actionName and Queue[insertPos].actionName ~= "" then
                -- 目标位置被占用，尝试找到第一个空位
                for i = 1, 4 do
                    local isEmpty = not Queue[i] or (not Queue[i].isHealingShamanSkill and (not Queue[i].actionName or Queue[i].actionName == ""))
                    if isEmpty then
                        insertPos = i
                        break
                    end
                end
            end
            
            -- 插入或移动技能
            if not alreadyInQueue or (existingSlot and existingSlot ~= insertPos) then
                self:CheckAndInsertSkill(skillData.skillDef, Queue, UI, dispName, skillData.targetUnit, insertPos)
            end
        end
    end
    
    -- 第五步：兜底逻辑 - 如果没有任何技能满足条件，但目标受伤，使用次级治疗波作为兜底
    if #skillsToInsert == 0 then
        -- 检查是否有受伤的友方目标
        local targetUnit = nil
        if self:IsValidHealingTarget("mouseover") then
            targetUnit = "mouseover"
        elseif self:IsValidHealingTarget("target") then
            targetUnit = "target"
        end
        
        -- 如果目标存在且受伤，使用次级治疗波作为兜底
        if targetUnit then
            -- 读取配置中的次级治疗波触发阈值
            local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
            local threshold = (db and db.healingShaman and db.healingShaman.lesserHealingWaveThreshold) or 90
            
            local targetHealthPercent = self:GetUnitHealthPercent(targetUnit)
            -- 只有当目标血量低于配置的阈值时才触发兜底
            if targetHealthPercent <= threshold then
                -- 找到次级治疗波的定义
                local lesserHealingWaveDef = nil
                for _, skillDef in ipairs(self.SkillDefinitions) do
                    if skillDef.actionName == "lesser_healing_wave" then
                        lesserHealingWaveDef = skillDef
                        break
                    end
                end
                
                if lesserHealingWaveDef then
                    -- 找到第一个空位插入
                    local insertPos = 1
                    for i = 1, 4 do
                        local isEmpty = not Queue[i] or (not Queue[i].isHealingShamanSkill and (not Queue[i].actionName or Queue[i].actionName == ""))
                        if isEmpty then
                            insertPos = i
                            break
                        end
                    end
                    
                    -- 插入次级治疗波作为兜底
                    self:CheckAndInsertSkill(lesserHealingWaveDef, Queue, UI, dispName, targetUnit, insertPos)
                    HekiliHelper:DebugPrint(string.format("|cFFFF00FF[HealingShaman]|r 使用次级治疗波作为兜底技能 (目标血量: %.1f%%, 阈值: %d%%)", targetHealthPercent, threshold))
                end
            end
        end
    end
end

-- 从队列中移除技能并恢复原始推荐
-- 参考MeleeTargetIndicator的实现，智能移除技能
function Module:RemoveSkillFromQueue(Queue, UI, slotIndex)
    if not Queue[slotIndex] or not Queue[slotIndex].isHealingShamanSkill then
        return
    end
    
    local slot = Queue[slotIndex]
    
    -- 如果有保存的原始推荐，恢复它
    if slot.originalRecommendation then
        local original = slot.originalRecommendation
        -- 清除当前技能
        for k, v in pairs(slot) do
            slot[k] = nil
        end
        -- 恢复原始推荐
        for k, v in pairs(original) do
            slot[k] = v
        end
        HekiliHelper:DebugPrint(string.format("|cFFFF0000[HealingShaman]|r 移除技能并恢复原始推荐 (位置 %d)", slotIndex))
    else
        -- 没有原始推荐，清除技能的关键属性
        -- 注意：不完全清除slot，只清除关键属性，让Hekili自然处理
        slot.actionName = nil
        slot.actionID = nil
        slot.texture = nil
        slot.isHealingShamanSkill = nil
        HekiliHelper:DebugPrint(string.format("|cFFFF0000[HealingShaman]|r 移除技能 (位置 %d)", slotIndex))
    end
    
    -- 设置NewRecommendations，确保UI更新
    UI.NewRecommendations = true
end

-- 检查并插入单个技能
function Module:CheckAndInsertSkill(skillDef, Queue, UI, dispName, targetUnit, insertPosition)
    -- 从Hekili获取技能信息
    local ability = self:GetSkillFromHekili(skillDef.actionName)
    
    -- 如果技能在Hekili中不存在，尝试创建虚拟ability或使用spellID获取信息
    if not ability then
        HekiliHelper:DebugPrint(string.format("|cFFFF0000[HealingShaman]|r 技能 %s 在Hekili中不存在，尝试创建虚拟ability", skillDef.displayName))
        
        -- 尝试从spellID获取技能信息
        local spellName, _, spellTexture = GetSpellInfo(skillDef.spellID)
        if spellName and spellTexture then
            -- 创建虚拟ability
            if Hekili and Hekili.Class and Hekili.Class.abilities then
                Hekili.Class.abilities[skillDef.actionName] = {
                    key = skillDef.actionName,
                    name = spellName,
                    texture = spellTexture,
                    id = skillDef.spellID,
                    cast = 0,
                    gcd = "off",
                }
                ability = Hekili.Class.abilities[skillDef.actionName]
                HekiliHelper:DebugPrint(string.format("|cFF00FF00[HealingShaman]|r 已创建虚拟ability: %s", skillDef.displayName))
            end
        end
        
        -- 如果仍然无法获取ability，返回
        if not ability then
            HekiliHelper:DebugPrint(string.format("|cFFFF0000[HealingShaman]|r 无法创建技能 %s 的ability，跳过插入", skillDef.displayName))
            return
        end
    end
    
    -- 检查技能是否可用
    if not self:IsSpellReady(skillDef.spellID) then
        HekiliHelper:DebugPrint(string.format("|cFFFF0000[HealingShaman]|r 技能 %s 冷却中", skillDef.displayName))
        return
    end
    
    -- 检查队列中是否已经有这个技能
    local alreadyHasSkill = false
    local skillSlot = nil
    for i = 1, 4 do
        if Queue[i] and Queue[i].actionName == skillDef.actionName then
            alreadyHasSkill = true
            skillSlot = i
            break
        end
    end
    
    -- 确定插入位置
    -- 如果指定了插入位置，使用它；否则根据优先级计算
    local insertIndex = insertPosition or 1
    
    -- 如果已经存在且位置正确，不需要更新
    if alreadyHasSkill and skillSlot == insertIndex then
        return
    end
    
    -- 如果技能已经在其他位置，需要移动到新位置
    -- 关键：不删除原位置的技能，而是直接在新位置插入
    -- 原位置的技能会在下次更新时自然消失（如果判断函数返回false）
    -- 这样可以避免删除操作导致整个队列消失
    if skillSlot and skillSlot ~= insertIndex then
        -- 不删除原位置的技能，让它在下次更新时自然消失
        -- 直接在新位置插入即可
    end
    
    -- 保存目标位置的原始推荐（如果不是我们要插入的技能）
    -- 关键：如果目标位置已经有我们的技能，不需要重新插入
    if Queue[insertIndex] and Queue[insertIndex].isHealingShamanSkill and Queue[insertIndex].actionName == skillDef.actionName then
        -- 技能已经存在且正确，只需要更新一些可能变化的属性
        local slot = Queue[insertIndex]
        slot.texture = ability.texture
        slot.actionID = skillDef.spellID
        return
    end
    
    local originalSlot = nil
    if Queue[insertIndex] and Queue[insertIndex].actionName and Queue[insertIndex].actionName ~= skillDef.actionName and not Queue[insertIndex].isHealingShamanSkill then
        originalSlot = {}
        for k, v in pairs(Queue[insertIndex]) do
            originalSlot[k] = v
        end
    end
    
    -- 创建或更新slot
    Queue[insertIndex] = Queue[insertIndex] or {}
    local slot = Queue[insertIndex]
    
    -- 设置技能信息
    slot.index = insertIndex
    slot.actionName = skillDef.actionName
    slot.actionID = skillDef.spellID
    slot.texture = ability.texture
    slot.caption = nil
    slot.indicator = nil
    local currentTime = GetTime()
    slot.time = 0
    slot.exact_time = currentTime
    slot.delay = 0
    slot.since = 0
    slot.resources = {}
    slot.depth = 0
    slot.keybind = nil
    slot.keybindFrom = nil
    slot.resource_type = nil
    slot.scriptType = nil
    slot.script = nil
    slot.hook = nil
    slot.display = dispName
    slot.pack = nil
    slot.list = nil
    slot.listName = nil
    slot.action = ability
    
    -- 标记为插入的技能，并保存原始推荐
    slot.isHealingShamanSkill = true
    slot.originalRecommendation = originalSlot
    
    -- 关键：参考MeleeTargetIndicator的实现，在插入技能时设置NewRecommendations
    -- 这确保了UI知道有新的推荐需要显示，避免队列消失的问题
    UI.NewRecommendations = true
    
    HekiliHelper:DebugPrint(string.format("|cFF00FF00[HealingShaman]|r 插入技能: %s", skillDef.displayName))
end
