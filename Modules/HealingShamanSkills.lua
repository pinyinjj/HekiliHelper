-- Modules/HealingShamanSkills.lua
-- 治疗萨满技能插入模块
-- 在优先级队列中插入治疗萨满推荐技能
-- 针对WLK版本的治疗萨满，提供常用治疗技能的推荐框架

local HekiliHelper = _G.HekiliHelper
if not HekiliHelper then return end

if not HekiliHelper.HealingShamanSkills then
    HekiliHelper.HealingShamanSkills = {}
end

local Module = HekiliHelper.HealingShamanSkills

-- 模块初始化
function Module:Initialize()
    if not Hekili or not Hekili.Update then return false end
    
    -- Hook Hekili.Update
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
-- 技能定义与逻辑
-- ============================================

-- WLK 治疗萨满技能 ID (Level 80)
-- 治疗波 Rank 14: 49272
-- 次级治疗波 Rank 9: 49276
-- 治疗链 Rank 4: 49273
-- 激流 Rank 1: 61295
-- 水之护盾 Rank 8: 57960
-- 大地之盾 Rank 5: 49284

Module.SkillDefinitions = {
    { actionName = "water_shield", spellID = 57960, priority = 1, checkFunc = function(self) return self:CheckWaterShield() end, displayName = "水之护盾" },
    { actionName = "earthliving_weapon", spellID = 51994, priority = 2, checkFunc = function(self) return self:CheckEarthlivingWeapon() end, displayName = "大地生命武器" },
    { actionName = "earth_shield", spellID = 49284, priority = 3, checkFunc = function(self) return self:CheckEarthShield() end, displayName = "大地之盾" },
    { actionName = "riptide", spellID = 61295, priority = 4, checkFunc = function(self) return self:CheckRiptide() end, displayName = "激流" },
    { actionName = "tide_force", spellID = 55198, priority = 4.5, checkFunc = function(self) return self:CheckTideForce() end, displayName = "潮汐之力" },
    { actionName = "healing_wave", spellID = 49272, priority = 5, checkFunc = function(self) return self:CheckHealingWave() end, displayName = "治疗波" },
    { actionName = "chain_heal", spellID = 49273, priority = 6, checkFunc = function(self) return self:CheckChainHeal() end, displayName = "治疗链" },
    { actionName = "lesser_healing_wave", spellID = 49276, priority = 7, checkFunc = function(self) return self:CheckLesserHealingWave() end, displayName = "次级治疗波" },
}

function Module:CheckChainHeal()
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    local threshold = (HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.chainHealThreshold) or 90
    if self:GetUnitHealthPercent(targetUnit) > threshold then return false end
    return true, targetUnit
end

function Module:CheckWaterShield()
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if not name then break end
        if spellId == 57960 or name:find("水之护盾") or name:find("Water Shield") then return false end
    end
    return true, "player"
end

function Module:CheckRiptide()
    if not self:IsSpellReady(61295) then return false end
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    local threshold = (HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.riptideThreshold) or 99
    if self:GetUnitHealthPercent(targetUnit) > threshold then return false end
    return true, targetUnit
end

function Module:CheckEarthShield()
    -- 仅检测焦点目标：是否存在、是否为友方、是否存活
    if UnitExists("focus") and UnitIsFriend("player", "focus") and not UnitIsDead("focus") then
        
        -- 遍历焦点目标身上的buff，高容错检查是否有大地之盾
        local hasEarthShield = false
        for i = 1, 40 do
            local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("focus", i)
            if not name then break end -- 没有更多buff了，跳出循环
            
            -- 同时匹配法术ID和中英文名称，兼容所有等级的大地之盾
            if spellId == 49284 or name:find("大地之盾") or name:find("Earth Shield") then 
                hasEarthShield = true
                break 
            end
        end

        -- 逻辑判断：有盾则停止推荐，没盾则推荐
        if hasEarthShield then
            return false -- 焦点有buff，不触发
        else
            return true, "focus" -- 焦点没有buff，触发，建议对焦点施放
        end
    end

    -- 如果没有焦点，或者焦点不是友方/已死亡，绝对不触发
    return false
end

function Module:CheckHealingWave()
    if HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.enableHealingWave == false then return false end
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    local threshold = (HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.healingWaveThreshold) or 30
    if self:GetUnitHealthPercent(targetUnit) > threshold then return false end
    return true, targetUnit
end

function Module:CheckLesserHealingWave()
    if HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.enableLesserHealingWave == false then return false end
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    local threshold = (HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.lesserHealingWaveThreshold) or 90
    if self:GetUnitHealthPercent(targetUnit) > threshold then return false end
    return true, targetUnit
end

function Module:CheckTideForce()
    if not self:IsSpellReady(55198) then return false end
    local threshold = (HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.tideForceThreshold) or 50
    if self:GetUnitHealthPercent("player") < threshold then return true, "player" end
    return false
end

function Module:CheckEarthlivingWeapon()
    local info = { GetWeaponEnchantInfo() }
    -- 大地生命附魔 ID 3350
    if not info[1] or info[4] ~= 3350 then return true, "player" end
    return false
end

-- ============================================
-- 辅助函数与插入逻辑
-- ============================================

function Module:GetUnitHealthPercent(unit)
    local h, m = UnitHealth(unit), UnitHealthMax(unit)
    return (m > 0) and (h / m * 100) or 100
end

function Module:HasBuff(unit, spellID)
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, sID = UnitBuff(unit, i)
        if not _ then break end
        if sID == spellID then return true end
    end
    return false
end

function Module:IsSpellReady(id)
    local s, d = GetSpellCooldown(id)
    return (not s or s == 0 or (s + d - GetTime() <= 0))
end

function Module:GetBestTarget()
    if UnitExists("mouseover") and UnitIsFriend("player", "mouseover") and not UnitIsDead("mouseover") then return "mouseover" end
    if UnitExists("target") and UnitIsFriend("player", "target") and not UnitIsDead("target") then return "target" end
    return "player"
end

function Module:GetSkillFromHekili(actionName)
    return Hekili.Class.abilities[actionName]
end

function Module:IsLearned(name, id)
    return IsSpellKnown(id) or GetSpellInfo(name) ~= nil
end

function Module:InsertHealingSkills()
    if not Hekili or not Hekili.DisplayPool then return end
    
    -- 检查整体开关
    if not HekiliHelper.DB or not HekiliHelper.DB.profile or not HekiliHelper.DB.profile.healingShaman or not HekiliHelper.DB.profile.healingShaman.enabled then
        return
    end

    for dispName, UI in pairs(Hekili.DisplayPool) do
        local lowerName = dispName:lower()
        if (lowerName == "primary" or lowerName == "aoe") and UI.Active and UI.alpha > 0 then
            local Queue = UI.Recommendations
            if not Queue then return end
            for _, skillDef in ipairs(self.SkillDefinitions) do
                if self:IsLearned(skillDef.displayName, skillDef.spellID) then
                    local should, target = skillDef.checkFunc(self)
                    if should then
                        local ability = self:GetSkillFromHekili(skillDef.actionName)
                        if not ability then
                            local n, _, t = GetSpellInfo(skillDef.spellID)
                            Hekili.Class.abilities[skillDef.actionName] = { key = skillDef.actionName, name = n, texture = t, id = skillDef.spellID, cast = 0, gcd = "off" }
                            ability = Hekili.Class.abilities[skillDef.actionName]
                        end
                        Queue[1] = Queue[1] or {}
                        if not Queue[1].isHealingShamanSkill then
                            Queue[1].originalRecommendation = {}
                            for k, v in pairs(Queue[1]) do Queue[1].originalRecommendation[k] = v end
                        end
                        local slot = Queue[1]
                        slot.actionName = skillDef.actionName
                        slot.actionID = skillDef.spellID
                        slot.texture = ability.texture
                        slot.isHealingShamanSkill = true
                        slot.display = dispName
                        slot.time = 0
                        slot.exact_time = GetTime()
                        UI.NewRecommendations = true
                        break
                    end
                end
            end
        end
    end
end
