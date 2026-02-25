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
    if not Hekili then return false end
    
    HekiliHelper:DebugPrint("|cFF00FF00[HealingPriest]|r 开始Hook Hekili.Update...")
    
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        -- 保存我们的技能
        local savedSkills = {}
        if Hekili and Hekili.DisplayPool then
            for dispName, UI in pairs(Hekili.DisplayPool) do
                if UI and UI.Recommendations then
                    local Queue = UI.Recommendations
                    savedSkills[dispName] = {}
                    for i = 1, 4 do
                        if Queue[i] and Queue[i].isHealingPriestSkill then
                            savedSkills[dispName][i] = {}
                            for k, v in pairs(Queue[i]) do
                                savedSkills[dispName][i][k] = v
                            end
                        end
                    end
                end
            end
        end
        
        local result = oldFunc(self, ...)
        
        C_Timer.After(0.001, function()
            -- 恢复被清除的技能
            if Hekili and Hekili.DisplayPool then
                for dispName, saved in pairs(savedSkills) do
                    local UI = Hekili.DisplayPool[dispName]
                    if UI and UI.Recommendations then
                        local Queue = UI.Recommendations
                        for i, savedSlot in pairs(saved) do
                            if not Queue[i] or not Queue[i].isHealingPriestSkill then
                                Queue[i] = {}
                                for k, v in pairs(savedSlot) do
                                    Queue[i][k] = v
                                end
                                UI.NewRecommendations = true
                            end
                        end
                    end
                end
            end
            
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
        checkFunc = function(self) return self:CheckInnerFire() end,
        displayName = "心灵之火"
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
    {
        actionName = "dispel_magic",
        spellID = 527,
        priority = 9,
        checkFunc = function(self) return self:CheckDispel() end,
        displayName = "驱散魔法"
    },
}

-- ============================================
-- 技能判断函数
-- ============================================

function Module:CheckInnerFire()
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingPriest or db.healingPriest.enabled == false then return false end
    
    if not HekiliHelper.HealingShamanSkills.HasBuff(self, "player", "心灵之火") and 
       not HekiliHelper.HealingShamanSkills.HasBuff(self, "player", "Inner Fire") then
        return true, "player"
    end
    return false
end

function Module:CheckShield()
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingPriest or db.healingPriest.enabled == false then return false end
    
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local hp = HekiliHelper.HealingShamanSkills.GetUnitHealthPercent(self, targetUnit)
    local threshold = db.healingPriest.shieldThreshold or 95
    
    if hp <= threshold then
        -- 检查是否有 灵魂虚弱 (Weakened Soul)
        local hasWeakenedSoul = false
        for i = 1, 40 do
            local name = UnitDebuff(targetUnit, i)
            if not name then break end
            if name == "灵魂虚弱" or name == "Weakened Soul" then
                hasWeakenedSoul = true
                break
            end
        end
        
        -- 检查是否已有盾
        local hasShield = HekiliHelper.HealingShamanSkills.HasBuff(self, targetUnit, "真言术：盾") or 
                          HekiliHelper.HealingShamanSkills.HasBuff(self, targetUnit, "Power Word: Shield")
        
        if not hasWeakenedSoul and not hasShield then
            return true, targetUnit
        end
    end
    return false
end

function Module:CheckPOM()
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingPriest or db.healingPriest.enabled == false then return false end
    
    if not self:IsSpellReady(48113) then return false end
    
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    -- 愈合祷言通常丢给坦或者正在掉血的人
    local hp = HekiliHelper.HealingShamanSkills.GetUnitHealthPercent(self, targetUnit)
    if hp <= (db.healingPriest.pomThreshold or 99) then
        return true, targetUnit
    end
    return false
end

function Module:CheckPenance()
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingPriest or db.healingPriest.enabled == false then return false end
    
    if not self:IsSpellReady(53007) then return false end
    
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local hp = HekiliHelper.HealingShamanSkills.GetUnitHealthPercent(self, targetUnit)
    if hp <= (db.healingPriest.penanceThreshold or 80) then
        return true, targetUnit
    end
    return false
end

function Module:CheckRenew()
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingPriest or db.healingPriest.enabled == false then return false end
    
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local hasRenew = HekiliHelper.HealingShamanSkills.HasBuff(self, targetUnit, "恢复") or 
                     HekiliHelper.HealingShamanSkills.HasBuff(self, targetUnit, "Renew")
                     
    if not hasRenew then
        local hp = HekiliHelper.HealingShamanSkills.GetUnitHealthPercent(self, targetUnit)
        if hp <= (db.healingPriest.renewThreshold or 90) then
            return true, targetUnit
        end
    end
    return false
end

function Module:CheckFlashHeal()
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingPriest or db.healingPriest.enabled == false then return false end
    
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local hp = HekiliHelper.HealingShamanSkills.GetUnitHealthPercent(self, targetUnit)
    if hp <= (db.healingPriest.flashHealThreshold or 70) then
        return true, targetUnit
    end
    return false
end

function Module:CheckGreaterHeal()
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingPriest or db.healingPriest.enabled == false then return false end
    
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    
    local hp = HekiliHelper.HealingShamanSkills.GetUnitHealthPercent(self, targetUnit)
    if hp <= (db.healingPriest.greaterHealThreshold or 40) then
        return true, targetUnit
    end
    return false
end

function Module:CheckCircleOfHealing()
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingPriest or db.healingPriest.enabled == false then return false end
    
    if not self:IsSpellReady(48089) then return false end
    
    -- 检查群体掉血
    local threshold = db.healingPriest.cohThreshold or 85
    local count = 0
    
    local units = HekiliHelper.HealingShamanSkills.GetFriendlyUnits(self)
    for _, unit in ipairs(units) do
        if HekiliHelper.HealingShamanSkills.IsValidHealingTarget(self, unit) then
            if HekiliHelper.HealingShamanSkills.GetUnitHealthPercent(self, unit) <= threshold then
                count = count + 1
            end
        end
    end
    
    if count >= 3 then
        return true, "mouseover" -- 通常环是对鼠标指向的人用
    end
    return false
end

function Module:CheckDispel()
    -- 简单的驱散检查逻辑可以以后扩展
    return false
end

-- ============================================
-- 辅助函数
-- ============================================

function Module:GetBestTarget()
    if HekiliHelper.HealingShamanSkills.IsValidHealingTarget(self, "mouseover") then
        return "mouseover"
    elseif HekiliHelper.HealingShamanSkills.IsValidHealingTarget(self, "target") then
        return "target"
    elseif HekiliHelper.HealingShamanSkills.IsValidHealingTarget(self, "focus") then
        return "focus"
    end
    return nil
end

function Module:IsSpellReady(spellID)
    return HekiliHelper.HealingShamanSkills.IsSpellReady(self, spellID)
end

-- ============================================
-- 主插入函数
-- ============================================

function Module:InsertHealingSkills()
    if not Hekili then return end
    
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.healingPriest or db.healingPriest.enabled == false then return end
    
    local displays = Hekili.DisplayPool
    if not displays then return end
    
    for dispName, UI in pairs(displays) do
        if (dispName == "Primary" or dispName == "AOE") and UI and UI.Active and UI.alpha > 0 then
            self:InsertSkillForDisplay(dispName, UI)
        end
    end
end

function Module:InsertSkillForDisplay(dispName, UI)
    local Queue = UI.Recommendations
    if not Queue then return end
    
    -- 获取符合条件的技能
    local skillsToInsert = {}
    for _, skillDef in ipairs(self.SkillDefinitions) do
        local shouldInsert, targetUnit = skillDef.checkFunc(self)
        if shouldInsert then
            table.insert(skillsToInsert, {def = skillDef, target = targetUnit})
        end
    end
    
    -- 插入逻辑参考萨满模块
    for i, data in ipairs(skillsToInsert) do
        if i > 4 then break end -- 最多占4个位
        
        local skillDef = data.def
        local targetUnit = data.target
        
        local ability = HekiliHelper.HealingShamanSkills.GetSkillFromHekili(self, skillDef.actionName)
        if not ability then
            -- 创建虚拟ability
            local spellName, _, spellTexture = GetSpellInfo(skillDef.spellID)
            if spellName then
                Hekili.Class.abilities[skillDef.actionName] = {
                    key = skillDef.actionName,
                    name = spellName,
                    texture = spellTexture,
                    id = skillDef.spellID,
                    cast = 0,
                    gcd = "off",
                }
                ability = Hekili.Class.abilities[skillDef.actionName]
            end
        end
        
        if ability and self:IsSpellReady(skillDef.spellID) then
            -- 寻找空位或覆盖
            local insertPos = i
            
            local originalSlot = nil
            if Queue[insertPos] and not Queue[insertPos].isHealingPriestSkill and Queue[insertPos].actionName ~= "" then
                originalSlot = {}
                for k, v in pairs(Queue[insertPos]) do originalSlot[k] = v end
            end
            
            Queue[insertPos] = Queue[insertPos] or {}
            local slot = Queue[insertPos]
            
            slot.index = insertPos
            slot.actionName = skillDef.actionName
            slot.actionID = skillDef.spellID
            slot.texture = ability.texture
            slot.time = 0
            slot.exact_time = GetTime()
            slot.display = dispName
            slot.isHealingPriestSkill = true
            slot.originalRecommendation = originalSlot
            slot.action = ability
            
            UI.NewRecommendations = true
        end
    end
end
