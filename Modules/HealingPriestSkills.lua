-- Modules/HealingPriestSkills.lua
-- 治疗牧师技能插入模块
-- 针对WLK版本的治疗牧师（神圣/戒律），提供常用治疗技能的推荐框架

local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.HealingPriestSkills then
            HH.HealingPriestSkills = {}
        end
    end)
    return
end

-- 创建模块对象
if not HekiliHelper.HealingPriestSkills then
    HekiliHelper.HealingPriestSkills = {}
end

local Module = HekiliHelper.HealingPriestSkills

-- 模块初始化
function Module:Initialize()
    if not Hekili then 
        HekiliHelper:Print("|cFFFF0000[HealingPriest]|r 错误: Hekili对象不存在")
        return false 
    end
    
    HekiliHelper:DebugPrint("|cFF00FF00[HealingPriest]|r 开始初始化...")
    
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        C_Timer.After(0.005, function()
            Module:InsertHealingSkills()
        end)
        return result
    end)
    
    return success
end

-- ============================================
-- 技能定义列表
-- ============================================

Module.SkillDefinitions = {
    {
        actionName = "inner_fire",
        spellID = 48168,
        priority = 1,
        checkFunc = function(self) return self:CheckBuff("player", 48168, "心灵之火", "Inner Fire") end,
        displayName = "心灵之火"
    },
    {
        actionName = "power_word_fortitude",
        spellID = 48063,
        priority = 1.1,
        checkFunc = function(self) return self:CheckBuff("player", 48063, "真言术：韧", "Power Word: Fortitude", 48161) end,
        displayName = "真言术：韧"
    },
    {
        actionName = "divine_spirit",
        spellID = 48073,
        priority = 1.2,
        checkFunc = function(self) return self:CheckBuff("player", 48073, "神圣之灵", "Divine Spirit", 48170) end,
        displayName = "神圣之灵"
    },
    {
        actionName = "power_word_shield",
        spellID = 48066,
        priority = 2,
        checkFunc = function(self) return self:CheckShield() end,
        displayName = "真言术：盾"
    },
    {
        actionName = "prayer_of_mending",
        spellID = 48113,
        priority = 3,
        checkFunc = function(self) return self:CheckPOM() end,
        displayName = "愈合祷言"
    },
    {
        actionName = "penance",
        spellID = 53007,
        priority = 4,
        checkFunc = function(self) return self:CheckPenance() end,
        displayName = "苦修"
    },
    {
        actionName = "renew",
        spellID = 48068,
        priority = 5,
        checkFunc = function(self) return self:CheckRenew() end,
        displayName = "恢复"
    },
    {
        actionName = "circle_of_healing",
        spellID = 48089,
        priority = 6,
        checkFunc = function(self) return self:CheckCircleOfHealing() end,
        displayName = "治疗环"
    },
    {
        actionName = "flash_heal",
        spellID = 48063,
        priority = 7,
        checkFunc = function(self) return self:CheckFlashHeal() end,
        displayName = "快速治疗"
    },
    {
        actionName = "greater_heal",
        spellID = 48071,
        priority = 8,
        checkFunc = function(self) return self:CheckGreaterHeal() end,
        displayName = "强效治疗术"
    },
}

-- ============================================
-- 技能判断函数
-- ============================================

-- 通用Buff检查 (支持小Buff和大Buff ID)
function Module:CheckBuff(unit, spellID, nameCN, nameEN, groupSpellID)
    -- 已经在战斗中或者没有Buff时推荐
    if not self:HasBuff(unit, spellID) then
        -- 如果有大Buff版本，也检查一下
        if groupSpellID and self:HasBuff(unit, groupSpellID) then
            return false
        end
        
        -- 检查名称 (双保险)
        if self:HasBuffByName(unit, nameCN) or self:HasBuffByName(unit, nameEN) then
            return false
        end
        
        return true, unit
    end
    return false
end

function Module:CheckShield()
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local hp = self:GetHealthPct(targetUnit)
    local threshold = HekiliHelper.DB.profile.healingPriest.shieldThreshold or 95
    
    if hp <= threshold then
        if not self:HasDebuff(targetUnit, 6788) and not self:HasBuff(targetUnit, 48066) then
            return true, targetUnit
        end
    end
    return false
end

function Module:CheckPOM()
    if not self:IsSpellReady(48113) then return false end
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    if self:GetHealthPct(targetUnit) <= (HekiliHelper.DB.profile.healingPriest.pomThreshold or 99) then
        return true, targetUnit
    end
    return false
end

function Module:CheckPenance()
    if not self:IsSpellReady(53007) then return false end
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    if self:GetHealthPct(targetUnit) <= (HekiliHelper.DB.profile.healingPriest.penanceThreshold or 80) then
        return true, targetUnit
    end
    return false
end

function Module:CheckRenew()
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    if not self:HasBuff(targetUnit, 48068) then
        if self:GetHealthPct(targetUnit) <= (HekiliHelper.DB.profile.healingPriest.renewThreshold or 90) then
            return true, targetUnit
        end
    end
    return false
end

function Module:CheckFlashHeal()
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    if self:GetHealthPct(targetUnit) <= (HekiliHelper.DB.profile.healingPriest.flashHealThreshold or 70) then
        return true, targetUnit
    end
    return false
end

function Module:CheckGreaterHeal()
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    if self:GetHealthPct(targetUnit) <= (HekiliHelper.DB.profile.healingPriest.greaterHealThreshold or 40) then
        return true, targetUnit
    end
    return false
end

function Module:CheckCircleOfHealing()
    if not self:IsSpellReady(48089) then return false end
    local count = 0
    local threshold = HekiliHelper.DB.profile.healingPriest.cohThreshold or 85
    local units = IsInRaid() and 40 or (IsInGroup() and 5 or 1)
    
    for i = 1, units do
        local u = (units == 1) and "player" or (IsInRaid() and "raid"..i or (i==5 and "player" or "party"..i))
        if self:IsFriendlyTarget(u) and self:GetHealthPct(u) <= threshold then
            count = count + 1
        end
    end
    return count >= 3, "mouseover"
end

-- ============================================
-- 工具函数
-- ============================================

function Module:IsFriendlyTarget(unit)
    return unit and UnitExists(unit) and UnitIsFriend("player", unit) and not UnitIsDead(unit) and UnitIsVisible(unit)
end

function Module:GetHealthPct(unit)
    local m = UnitHealthMax(unit)
    return (m > 0) and (UnitHealth(unit) / m * 100) or 100
end

function Module:HasBuff(unit, spellID)
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, sID = UnitBuff(unit, i)
        if not _ then break end
        if sID == spellID then return true end
    end
    return false
end

function Module:HasBuffByName(unit, name)
    if not name then return false end
    for i = 1, 40 do
        local bName = UnitBuff(unit, i)
        if not bName then break end
        if bName == name then return true end
    end
    return false
end

function Module:HasDebuff(unit, spellID)
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, sID = UnitDebuff(unit, i)
        if not _ then break end
        if sID == spellID then return true end
    end
    return false
end

function Module:IsSpellReady(spellID)
    local s, d = GetSpellCooldown(spellID)
    return (not s or s == 0 or (s + d - GetTime() <= 0))
end

function Module:GetBestTarget()
    if self:IsFriendlyTarget("mouseover") then return "mouseover" end
    if self:IsFriendlyTarget("target") then return "target" end
    if self:IsFriendlyTarget("focus") then return "focus" end
    return nil
end

-- ============================================
-- 主逻辑
-- ============================================

function Module:InsertHealingSkills()
    if not Hekili or not Hekili.DisplayPool then return end
    local db = HekiliHelper.DB.profile
    if not db.enabled or not db.healingPriest or not db.healingPriest.enabled then return end
    
    for dispName, UI in pairs(Hekili.DisplayPool) do
        if (dispName == "Primary" or dispName == "AOE") and UI and UI.Active and UI.alpha > 0 then
            local Queue = UI.Recommendations
            if not Queue then return end
            
            -- 清除旧牧师技能
            for i = 1, 4 do
                if Queue[i] and Queue[i].isHealingPriestSkill then Queue[i] = nil end
            end
            
            local skillsFound = 0
            for _, skillDef in ipairs(self.SkillDefinitions) do
                -- 必须已学习
                if GetSpellInfo(skillDef.spellID) then
                    local shouldInsert, targetUnit = skillDef.checkFunc(self)
                    if shouldInsert and skillsFound < 4 then
                        skillsFound = skillsFound + 1
                        
                        local ability = Hekili.Class.abilities[skillDef.actionName]
                        if not ability then
                            local n, _, t = GetSpellInfo(skillDef.spellID)
                            Hekili.Class.abilities[skillDef.actionName] = {
                                key = skillDef.actionName, name = n, texture = t, id = skillDef.spellID, cast = 0, gcd = "off"
                            }
                            ability = Hekili.Class.abilities[skillDef.actionName]
                        end
                        
                        Queue[skillsFound] = Queue[skillsFound] or {}
                        local slot = Queue[skillsFound]
                        slot.index = skillsFound
                        slot.actionName = skillDef.actionName
                        slot.actionID = skillDef.spellID
                        slot.texture = ability.texture
                        slot.time = 0
                        slot.exact_time = GetTime()
                        slot.display = dispName
                        slot.isHealingPriestSkill = true
                        slot.action = ability
                        
                        UI.NewRecommendations = true
                        HekiliHelper:DebugPrint(string.format("|cFF00FFFF[HealingPriest]|r 推荐 %s", skillDef.displayName))
                    end
                end
            end
        end
    end
end
