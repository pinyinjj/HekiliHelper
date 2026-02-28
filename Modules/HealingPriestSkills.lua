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
        C_Timer.After(0.001, function()
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
        checkFunc = function(self) 
            -- 如果拥有 邪能智力 (Fel Intellect) ID: 54424，不推荐神圣之灵
            if self:HasBuff("player", 54424) or self:HasBuffByName("player", "邪能智力") or self:HasBuffByName("player", "Fel Intellect") then
                return false
            end
            -- 检查自身是否拥有神圣之灵或其群体版本（精神祷言）
            return self:CheckBuff("player", 48073, "神圣之灵", "Divine Spirit", 48170) 
        end,
        displayName = "神圣之灵"
    },
    {
        actionName = "flash_heal",
        spellID = 48061,
        priority = 1.5,
        checkFunc = function(self) return self:CheckSurgeOfLight() end,
        displayName = "快速治疗(瞬发)"
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
        spellID = 48061,
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
    
    local missingHP = self:GetMissingHealth(targetUnit)
    local sp = self:GetSpellPower()
    local coeff = HekiliHelper.DB.profile.healingPriest.effectiveCoefficient or 0.8
    
    if missingHP >= (sp * coeff) then
        -- 虚弱灵魂 (Weakened Soul) ID: 6788
        local hasWeakenedSoul = self:HasDebuff(targetUnit, 6788)
        if not hasWeakenedSoul then
            local wsName = GetSpellInfo(6788)
            if wsName and self:HasDebuffByName(targetUnit, wsName) then
                hasWeakenedSoul = true
            end
        end

        if not hasWeakenedSoul then
            -- 检查盾Buff (通过名称检查以支持所有等级)
            local pwsName = GetSpellInfo(17) -- Rank 1 ID to get name
            local hasShield = false
            if pwsName and self:HasBuffByName(targetUnit, pwsName) then
                hasShield = true
            elseif self:HasBuff(targetUnit, 48066) then
                hasShield = true
            end
            
            if not hasShield then
                return true, targetUnit
            end
        end
    end
    return false
end

function Module:CheckSurgeOfLight()
    -- 圣光涌动 (Surge of Light) ID: 33151
    local expirationTime = self:GetBuffExpirationTime("player", 33151)
    if not expirationTime then
        local surgeName = GetSpellInfo(33151)
        if surgeName then
            expirationTime = self:GetBuffExpirationTimeByName("player", surgeName)
        end
    end

    if expirationTime then
        local remaining = expirationTime - GetTime()
        if remaining > 0 then
            -- 动态系数逻辑：10秒=100%, 1秒=10% (线性衰减)
            -- 每0.5秒跳动一次由Hekili.Update频率保证（通常很高）
            local timeFactor = math.max(0.1, math.min(1.0, remaining / 10))
            
            local targetUnit = self:GetBestTarget()
            if targetUnit then
                local missingHP = self:GetMissingHealth(targetUnit)
                local sp = self:GetSpellPower()
                local baseCoeff = HekiliHelper.DB.profile.healingPriest.effectiveCoefficient or 0.8
                local dynamicCoeff = baseCoeff * timeFactor
                
                if missingHP >= (sp * dynamicCoeff) then
                    return true, targetUnit
                end
            end
        end
    end
    return false
end

function Module:CheckPOM()
    if not self:IsSpellReady(48113) then return false end
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local missingHP = self:GetMissingHealth(targetUnit)
    local sp = self:GetSpellPower()
    local coeff = HekiliHelper.DB.profile.healingPriest.effectiveCoefficient or 0.8
    
    if missingHP >= (sp * coeff) then
        return true, targetUnit
    end
    return false
end

function Module:CheckPenance()
    if not self:IsSpellReady(53007) then return false end
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local missingHP = self:GetMissingHealth(targetUnit)
    local sp = self:GetSpellPower()
    local coeff = HekiliHelper.DB.profile.healingPriest.effectiveCoefficient or 0.8
    
    if missingHP >= (sp * coeff) then
        return true, targetUnit
    end
    return false
end

function Module:CheckRenew()
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local renewName = GetSpellInfo(139) -- Rank 1 ID to get name
    local hasRenew = false
    if renewName and self:HasBuffByName(targetUnit, renewName) then
        hasRenew = true
    elseif self:HasBuff(targetUnit, 48068) then
        hasRenew = true
    end
    
    if not hasRenew then
        local missingHP = self:GetMissingHealth(targetUnit)
        local sp = self:GetSpellPower()
        local coeff = HekiliHelper.DB.profile.healingPriest.effectiveCoefficient or 0.8
        
        if missingHP >= (sp * coeff) then
            return true, targetUnit
        end
    end
    return false
end

function Module:CheckFlashHeal()
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local missingHP = self:GetMissingHealth(targetUnit)
    local sp = self:GetSpellPower()
    local coeff = HekiliHelper.DB.profile.healingPriest.effectiveCoefficient or 0.8
    
    if missingHP >= (sp * coeff) then
        return true, targetUnit
    end
    return false
end

function Module:CheckGreaterHeal()
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local missingHP = self:GetMissingHealth(targetUnit)
    local sp = self:GetSpellPower()
    local coeff = HekiliHelper.DB.profile.healingPriest.effectiveCoefficient or 0.8
    
    -- 强效治疗术通常需要更大的缺口，这里可以根据业务需求调整或者保持统一系数
    if missingHP >= (sp * coeff * 1.5) then -- 假设强效治疗需要1.5倍的缺口
        return true, targetUnit
    end
    return false
end

function Module:CheckCircleOfHealing()
    if not self:IsSpellReady(48089) then return false end
    local count = 0
    local sp = self:GetSpellPower()
    local coeff = HekiliHelper.DB.profile.healingPriest.effectiveCoefficient or 0.8
    local threshold = sp * coeff
    
    local units = IsInRaid() and 40 or (IsInGroup() and 5 or 1)
    
    for i = 1, units do
        local u = (units == 1) and "player" or (IsInRaid() and "raid"..i or (i==5 and "player" or "party"..i))
        if self:IsFriendlyTarget(u) and self:GetMissingHealth(u) >= threshold then
            count = count + 1
        end
    end
    
    if count >= 3 then
        local targetUnit = self:GetBestTarget()
        return targetUnit ~= nil, targetUnit
    end
    return false
end

-- ============================================
-- 工具函数
-- ============================================

function Module:GetSpellPower()
    -- 获取治疗强度 (Spell Bonus Healing)
    return GetSpellBonusHealing() or 0
end

function Module:GetMissingHealth(unit)
    if not unit or not UnitExists(unit) then return 0 end
    return UnitHealthMax(unit) - UnitHealth(unit)
end

function Module:GetBuffExpirationTime(unit, spellID)
    for i = 1, 40 do
        local _, _, _, _, _, expirationTime, _, _, _, sID = UnitBuff(unit, i)
        if not _ then break end
        if sID == spellID then return expirationTime end
    end
    return nil
end

function Module:GetBuffExpirationTimeByName(unit, name)
    if not name then return nil end
    for i = 1, 40 do
        local bName, _, _, _, _, expirationTime = UnitBuff(unit, i)
        if not bName then break end
        if bName == name then return expirationTime end
    end
    return nil
end

function Module:IsFriendlyTarget(unit)
    if not (unit and UnitExists(unit) and UnitIsFriend("player", unit) and not UnitIsDead(unit) and UnitIsVisible(unit)) then
        return false
    end
    
    -- 检查距离（40码范围内）
    local RC = LibStub and LibStub("LibRangeCheck-2.0")
    if RC then
        local minRange, maxRange = RC:GetRange(unit)
        if maxRange and maxRange > 40 then
            return false
        end
    end
    
    return true
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

function Module:HasDebuffByName(unit, name)
    if not name then return false end
    for i = 1, 40 do
        local bName = UnitDebuff(unit, i)
        if not bName then break end
        if bName == name then return true end
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
    if self:IsFriendlyTarget("player") then return "player" end
    return nil
end

function Module:IsLearned(name, id)
    -- 首先尝试通过 ID 检查（适用于天赋技能或无等级技能）
    if IsSpellKnown(id) then return true end
    -- 尝试通过名称检查（适用于有多个等级的技能，只要学习了任意等级，GetSpellInfo(name) 就会返回有效值）
    local spellName = GetSpellInfo(name)
    return spellName ~= nil
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
                -- 使用增强的已学习检测，支持多等级技能
                if self:IsLearned(skillDef.displayName, skillDef.spellID) then
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
