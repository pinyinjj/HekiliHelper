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

    self.lastActionTime = GetTime()

    -- 注册事件以追踪玩家手动施法
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        self.eventFrame:SetScript("OnEvent", function(f, event, unit, ...)
            self.lastActionTime = GetTime()
        end)
    end

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
    { actionName = "ancestral_spirit", spellID = 2008, priority = 0.5, checkFunc = function(self) return self:CheckResurrection() end, displayName = "先祖之魂" },
    { actionName = "water_shield", spellID = 57960, priority = 1, checkFunc = function(self) return self:CheckWaterShield() end, displayName = "水之护盾" },
    { actionName = "earthliving_weapon", spellID = 51994, priority = 2, checkFunc = function(self) return self:CheckEarthlivingWeapon() end, displayName = "大地生命武器" },
    { actionName = "earth_shield", spellID = 49284, priority = 3, checkFunc = function(self) return self:CheckEarthShield() end, displayName = "大地之盾" },
    { actionName = "mana_tide", spellID = 16190, priority = 3.5, checkFunc = function(self) return self:CheckManaTide() end, displayName = "法力之潮图腾" },
    { actionName = "riptide", spellID = 61295, priority = 4, checkFunc = function(self) return self:CheckRiptide() end, displayName = "激流" },
    { actionName = "tide_force", spellID = 55198, priority = 4.5, checkFunc = function(self) return self:CheckTideForce() end, displayName = "潮汐之力" },
    { actionName = "healing_wave", spellID = 49272, priority = 5, checkFunc = function(self) return self:CheckHealingWave() end, displayName = "治疗波" },
    { actionName = "chain_heal", spellID = 49273, priority = 6, checkFunc = function(self) return self:CheckChainHeal() end, displayName = "治疗链" },
    { actionName = "lesser_healing_wave", spellID = 49276, priority = 7, checkFunc = function(self) return self:CheckLesserHealingWave() end, displayName = "次级治疗波" },
}

function Module:CheckResurrection()
    if InCombatLockdown() then return false end
    if self:IsEatingOrDrinking() then return false end

    local targetUnit = self:GetDeadTarget()
    if not targetUnit then return false end

    -- 检查距离 (30码)
    local minRange, maxRange = self:GetUnitRange(targetUnit)
    if maxRange and maxRange > 30 then return false end
    
    -- 检查可视
    if not UnitIsVisible(targetUnit) then return false end

    return true, targetUnit
end

function Module:IsEatingOrDrinking()
-- ... (rest of the function)
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if not name then break end
        -- 常用吃喝 Buff 检查
        if name:find("进食") or name:find("饮水") or name:find("进餐") or 
           name:find("Food") or name:find("Drink") or name:find("Refreshment") then
            return true
        end
    end
    return false
end

function Module:GetDeadTarget()
    if UnitExists("mouseover") and UnitIsFriend("player", "mouseover") and UnitIsDead("mouseover") then return "mouseover" end
    if UnitExists("target") and UnitIsFriend("player", "target") and UnitIsDead("target") then return "target" end
    return nil
end

function Module:CheckChainHeal()
    local targetUnit = self:GetBestTarget()
    if not targetUnit then return false end
    local threshold = (HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.chainHealThreshold) or 90
    if self:GetUnitHealthPercent(targetUnit) > threshold then return false end
    return true, targetUnit
end

function Module:CheckManaTide()
    if HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.enableManaTide == false then return false end
    if not self:IsSpellReady(16190) then return false end

    local threshold = (HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.manaTideThreshold) or 30
    if self:GetUnitManaPercent("player") < threshold then return true, "player" end
    return false
end

function Module:CheckWaterShield()
    -- 如果技能正在冷却中或被沉默，则不推荐
    if not self:IsSpellReady(57960) then return false end

    local isUsable, noMana = IsUsableSpell(57960)
    if not isUsable and not noMana then
        return false
    end

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

        -- 检查技能是否可用（沉默、蓝量等）
        local isUsable, noMana = IsUsableSpell(49284)
        if not isUsable and not noMana then return false end

        -- 检查距离
        local minRange, maxRange = self:GetUnitRange("focus")
        if maxRange and maxRange > 40 then return false end

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

function Module:GetUnitRange(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return nil, nil end

    -- 使用与 RangeDisplay 相同的 LibRangeCheck-3.0
    local rc = LibStub("LibRangeCheck-3.0", true) or LibStub("LibRangeCheck-2.0", true)
    if rc then
        return rc:GetRange(unit)
    end

    return nil, nil
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
    if HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.enableTideForce == false then return false end
    if not self:IsSpellReady(55198) then return false end

    local threshold = (HekiliHelper.DB.profile.healingShaman and HekiliHelper.DB.profile.healingShaman.tideForceThreshold) or 50
    local lowHealthCount = self:GetLowHealthGroupMembersCount(threshold)

    local isRaid = IsInRaid()
    local groupSize = isRaid and GetNumGroupMembers() or GetNumSubgroupMembers() + 1        

    if isRaid then
        -- 团队状态：1/3以上成员生命值低于阈值
        if lowHealthCount >= (groupSize / 3) then return true, "player" end
    else
        -- 小队状态：一半以上成员生命值低于阈值
        if lowHealthCount >= (groupSize / 2) then return true, "player" end
    end

    -- 自身生命值低于阈值也触发
    if self:GetUnitHealthPercent("player") < threshold then return true, "player" end       

    return false
end

function Module:GetLowHealthGroupMembersCount(threshold)
    local count = 0
    local isRaid = IsInRaid()
    local prefix = isRaid and "raid" or "party"
    local numMembers = isRaid and GetNumGroupMembers() or GetNumSubgroupMembers()

    -- 检查队友
    for i = 1, numMembers do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsDead(unit) and self:GetUnitHealthPercent(unit) < threshold then
            count = count + 1
        end
    end

    -- 检查自己 (party模式下numMembers不包含自己)
    if not isRaid then
        if not UnitIsDead("player") and self:GetUnitHealthPercent("player") < threshold then
            count = count + 1
        end
    end

    return count
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

function Module:GetUnitManaPercent(unit)
    local m, mx = UnitPower(unit), UnitPowerMax(unit)
    return (mx > 0) and (m / mx * 100) or 100
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

            local foundAction = false
            for _, skillDef in ipairs(self.SkillDefinitions) do
                if self:IsLearned(skillDef.displayName, skillDef.spellID) then
                    local should, target = skillDef.checkFunc(self)
                    if should then
                        self:InjectSkill(Queue, UI, dispName, skillDef)
                        foundAction = true
                        self.lastActionTime = GetTime() -- 更新动作时间
                        break
                    end
                end
            end

            -- 如果没有推荐任何技能，且在战斗中超过 4.5 秒，强制推荐治疗链
            if not foundAction then
                if InCombatLockdown() then
                    if GetTime() - (self.lastActionTime or 0) > 4.5 then
                        local chainHealDef
                        for _, def in ipairs(self.SkillDefinitions) do
                            if def.actionName == "chain_heal" then
                                chainHealDef = def
                                break
                            end
                        end
                        
                        if chainHealDef and self:IsLearned(chainHealDef.displayName, chainHealDef.spellID) then
                            self:InjectSkill(Queue, UI, dispName, chainHealDef, true)
                        end
                    end
                else
                    -- 非战斗状态不断重置时间，确保进入战斗时从 0 开始计算
                    self.lastActionTime = GetTime()
                end
            end
        end
    end
end

function Module:InjectSkill(Queue, UI, dispName, skillDef, isForced)
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
    slot.isForcedRecommendation = isForced or false
    slot.display = dispName
    slot.time = 0
    slot.exact_time = GetTime()
    UI.NewRecommendations = true
end
