-- Modules/RetPaladinSkills.lua
-- 惩戒骑士技能插入模块
-- 在优先级队列中插入惩戒骑士推荐技能

local HekiliHelper = _G.HekiliHelper
if not HekiliHelper then return end

if not HekiliHelper.RetPaladinSkills then
    HekiliHelper.RetPaladinSkills = {}
end

local Module = HekiliHelper.RetPaladinSkills

-- TTD 跟踪数据
Module.ttdData = { lastHP = 0, lastTime = 0, ttd = 999, guid = nil }

-- 模块初始化
function Module:Initialize()
    if not Hekili or not Hekili.Update then return false end
    
    -- Hook Hekili.Update
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        -- 移除 Timer，直接同步执行，解决闪烁问题
        Module:InsertPaladinSkills()
        return result
    end)
    
    return success
end

-- ============================================
-- 技能定义与逻辑
-- ============================================

Module.SkillDefinitions = {
    -- 生存/爆发
    { actionName = "will_to_survive", spellID = 59752, priority = 1, checkFunc = function(self) return self:CheckWillToSurvive() end, displayName = "生存意志" },
    { actionName = "avenging_wrath", spellID = 31884, priority = 1.1, checkFunc = function(self) return self:CheckAvengingWrath() end, displayName = "复仇之怒" },
    { actionName = "divine_plea", spellID = 54428, priority = 1.2, checkFunc = function(self) return self:CheckDivinePlea() end, displayName = "神圣恳求" },
    { actionName = "lights_plea", spellID = 1298728, priority = 1.3, checkFunc = function(self) return self:CheckLightsPlea() end, displayName = "祈求圣光" },
    
    -- 核心输出 (高优先级)
    { actionName = "hammer_of_wrath", spellID = 48806, priority = 2, checkFunc = function(self) return self:CheckHammerOfWrath() end, displayName = "愤怒之锤" },
    
    -- 十字军优先模式 (正义 < 5层时)
    { actionName = "crusader_strike_high", spellID = 35395, priority = 3, checkFunc = function(self) return self:CheckCrusaderStrike(true) end, displayName = "十字军打击(叠层)" },
    { actionName = "divine_storm_low", spellID = 53385, priority = 3.1, checkFunc = function(self) return self:CheckDivineStorm(false) end, displayName = "神圣风暴(填充)" },
    
    -- 神圣风暴优先模式 (正义 >= 5层时)
    { actionName = "divine_storm_high", spellID = 53385, priority = 3.5, checkFunc = function(self) return self:CheckDivineStorm(true) end, displayName = "神圣风暴(爆发)" },
    { actionName = "crusader_strike_low", spellID = 35395, priority = 3.6, checkFunc = function(self) return self:CheckCrusaderStrike(false) end, displayName = "十字军打击(填充)" },
    
    -- 动态驱邪术 (对亡灵/恶魔优先级极高)
    { actionName = "exorcism_high", spellID = 48801, priority = 4.5, checkFunc = function(self) return self:CheckExorcism(true) end, displayName = "驱邪术(亡灵/恶魔)" },
    
    -- 填充技能
    { actionName = "judgement_of_light", spellID = 20271, priority = 5, checkFunc = function(self) return self:CheckJudgement(20271) end, displayName = "圣光审判" },
    { actionName = "judgement_of_wisdom", spellID = 53408, priority = 5.1, checkFunc = function(self) return self:CheckJudgement(53408) end, displayName = "智慧审判" },
    
    -- 普通驱邪术
    { actionName = "exorcism", spellID = 48801, priority = 6, checkFunc = function(self) return self:CheckExorcism(false) end, displayName = "驱邪术" },
    
    { actionName = "consecration", spellID = 48819, priority = 7, checkFunc = function(self) return self:CheckConsecration() end, displayName = "奉献" },
    { actionName = "holy_wrath", spellID = 48817, priority = 8, checkFunc = function(self) return self:CheckHolyWrath() end, displayName = "神圣愤怒" },
    
    -- 辅助/其他
    { actionName = "divine_shield", spellID = 642, priority = 9, checkFunc = function(self) return self:CheckDivineShield() end, displayName = "圣盾术" },
    { actionName = "hand_of_salvation", spellID = 1038, priority = 10, checkFunc = function(self) return self:CheckHandOfSalvation() end, displayName = "拯救之手" },
    { actionName = "lionheart", spellID = 20599, priority = 11, checkFunc = function(self) return self:CheckLionheart() end, displayName = "狮心" },
}

function Module:IsInRange(id, unit)
    unit = unit or "target"
    if not UnitExists(unit) then return false end
    -- 使用十字军打击 (35395) 作为近战范围参考，如果传入 ID 为 nil
    local spell = id and GetSpellInfo(id) or GetSpellInfo(35395)
    return IsSpellInRange(spell, unit) == 1
end

function Module:IsBoss(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return false end
    local level = UnitLevel(unit)
    local classification = UnitClassification(unit)
    -- -1 表示首领级别，83 是 WLK 首领等级
    return level == -1 or level == 83 or classification == "worldboss" or classification == "boss"
end

function Module:UpdateTTD()
    local guid = UnitGUID("target")
    if not guid then 
        self.ttdData.ttd = 999
        self.ttdData.guid = nil
        return 
    end
    
    local hp = UnitHealth("target")
    local now = GetTime()
    
    if self.ttdData.guid ~= guid then
        self.ttdData.guid = guid
        self.ttdData.lastHP = hp
        self.ttdData.lastTime = now
        self.ttdData.ttd = 999
    else
        local diff = self.ttdData.lastHP - hp
        local timeDiff = now - self.ttdData.lastTime
        
        if timeDiff >= 1 and diff > 0 then
            local ps = diff / timeDiff
            self.ttdData.ttd = hp / ps
            self.ttdData.lastHP = hp
            self.ttdData.lastTime = now
        end
    end
end

function Module:GetTTD()
    return self.ttdData.ttd
end

function Module:CheckWillToSurvive()
    -- 如果玩家生命值低于 30% 且被控制，简单判断
    if self:GetUnitHealthPercent("player") < 30 then
        -- 这里可以添加更复杂的控制检测
        return false
    end
    return false
end

function Module:GetBuffStacks(unit, spellID)
    for i = 1, 40 do
        local _, _, count, _, _, _, _, _, _, sID = UnitBuff(unit, i)
        if not _ then break end
        if sID == spellID then return count or 0 end
    end
    return 0
end

function Module:CheckBurstConditions()
    -- 1. 必须是 Boss 目标 且 存活 (非 Boss 战不开启爆发)
    if not self:IsBoss("target") or UnitIsDead("target") then return false end
    
    -- 2. 位于爆发技能范围内 (10码参考，对齐神圣风暴和审判)
    if not self:IsInRange(20271) then return false end

    return true
end

function Module:CheckAvengingWrath()
    -- 判断复仇之怒技能可用性
    if not self:IsSpellReady(31884) then return false end
    
    -- 1. 虔诚 (1298725) 存在五层 (复仇之怒特有判断)
    if self:GetBuffStacks("player", 1298725) < 5 then return false end

    -- 2. 使用统一的爆发前置判断函数 (Boss 战、目标、距离)
    if self:CheckBurstConditions() then
        return true, "target"
    end
    return false
end

function Module:GetBuffTimeLeft(unit, spellID)
    for i = 1, 40 do
        local _, _, _, _, _, expirationTime, _, _, _, sID = UnitBuff(unit, i)
        if not _ then break end
        if sID == spellID then
            local now = GetTime()
            return (expirationTime > now) and (expirationTime - now) or 0
        end
    end
    return 0
end

function Module:CheckLightsPlea()
    -- 1. 技能可用性
    if not self:IsSpellReady(1298728) then return false end
    
    -- 2. 处于爆发前置状态
    if not self:CheckBurstConditions() then return false end
    
    -- 3. 玩家没有在移动 (速度为 0) - 祈求圣光特有要求
    if GetUnitSpeed("player") > 0 then return false end
    
    -- 4. 玩家有五层正义 (1299090) 且持续时间超过 5 秒
    if self:GetBuffStacks("player", 1299090) < 5 then return false end
    if self:GetBuffTimeLeft("player", 1299090) <= 5 then return false end
    
    -- 5. 玩家没有 debuff 圣光重担 (1299086)
    if self:HasDebuff("player", 1299086) then return false end
    
    return true, "player"
end

function Module:CheckDivinePlea()
    if not self:IsSpellReady(54428) then return false end
    
    local manaPct = self:GetUnitManaPercent("player")
    
    -- 爆发期特殊处理：蓝量超过 20% 时不使用神圣恳求 (防止减疗影响爆发)
    if self:CheckBurstConditions() then
        if manaPct > 20 then return false end
    end
    
    -- 基础判断：魔法值低于 50% 时推荐
    if manaPct < 50 then return true, "player" end
    
    return false
end

function Module:CheckDivineStorm(requireStacks)
    -- 1. 基础可用性 (存活 + 10码判定)
    if not UnitExists("target") or UnitIsDead("target") then return false end
    if not self:IsInRange(20271) then return false end
    if not self:IsSpellReady(53385) then return false end
    
    -- 2. 动态层数逻辑
    local stacks = self:GetBuffStacks("player", 1299090)
    if requireStacks then
        -- 高优先级分支：仅在 >= 5层时触发
        return stacks >= 5, "player"
    else
        -- 低优先级分支：仅在 < 5层时作为填充触发
        return stacks < 5, "player"
    end
end

function Module:CheckCrusaderStrike(requireHighPriority)
    -- 1. 基础可用性 (存活 + 5码近战判定)
    if not self:CheckMeleeConditions(35395) then return false end
    
    -- 2. 动态层数逻辑
    local stacks = self:GetBuffStacks("player", 1299090)
    if requireHighPriority then
        -- 高优先级分支：仅在 < 5层时触发 (为了快速叠层)
        return stacks < 5, "target"
    else
        -- 低优先级分支：仅在 >= 5层时作为填充触发
        return stacks >= 5, "target"
    end
end

function Module:CheckMeleeConditions(id)
    -- 1. 目标存活
    if not UnitExists("target") or UnitIsDead("target") then return false end
    
    -- 2. 纯近战范围判断 (5码参考)
    if not self:IsInRange(id) then return false end
    
    -- 3. 技能可用 (冷却结束)
    if not self:IsSpellReady(id) then return false end
    
    return true
end

function Module:CheckHammerOfWrath()
    -- 基础判断：远程条件 (敌对、存活、距离、可用)
    -- 愤怒之锤原生即为 30 码射程，通过 CheckRemoteConditions 自动校验
    if not self:CheckRemoteConditions(48806) then return false end
    
    -- 特有判断：生命值 < 20%
    if self:GetUnitHealthPercent("target") < 20 then
        return true, "target"
    end
    return false
end

function Module:GetSpellCooldownLeft(id)
    local start, duration = GetSpellCooldown(id)
    if not start or start == 0 then return 0 end
    local cd = start + duration - GetTime()
    return cd > 0 and cd or 0
end

function Module:CheckRemoteConditions(id, rangeLimit)
    -- 1. 当前目标敌对且存活
    if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then 
        return false 
    end
    
    -- 2. 距离判断
    local spellName = GetSpellInfo(id)
    if not spellName then return false end
    
    -- 基础射程检查
    if IsSpellInRange(spellName, "target") ~= 1 then return false end
    
    -- 额外范围参数控制 (如果有特定要求，比如 10/30 码)
    -- 这里通过 LibRangeCheck 或基础 IsSpellInRange 已经涵盖了技能原生范围
    -- 如果需要强制数值限制，通常依赖于特定技能的射程参考
    
    -- 3. 技能可用
    if not self:IsSpellReady(id) then return false end
    
    return true
end

function Module:CheckJudgement(id)
    -- 基础远程条件 (敌对、存活、距离、可用)
    if not self:CheckRemoteConditions(id) then return false end
    
    -- 逻辑：作为填充技能，不再强制要求十字军/风暴在CD（已通过优先级表控制）
    local manaPct = self:GetUnitManaPercent("player")
    if id == 20271 then -- 圣光审判
        return manaPct >= 80, "target"
    elseif id == 53408 then -- 智慧审判
        return manaPct < 80, "target"
    end
    
    return false
end

function Module:CheckExorcism(isHighPriority)
    -- 1. 基础可用性与远程条件 (敌对、存活、30码射程、可用)
    if not self:CheckRemoteConditions(48801) then return false end
    
    -- 2. 检查战争艺术触发 (59578)
    if not self:HasBuff("player", 59578) then return false end

    -- 3. 动态优先级逻辑
    local type = UnitCreatureType("target")
    local isUndeadOrDemon = (type == "Undead" or type == "Demon" or type == "亡灵" or type == "恶魔")
    
    if isHighPriority then
        -- 高优先级分支：仅对亡灵/恶魔返回 True
        return isUndeadOrDemon, "target"
    else
        -- 普通优先级分支：仅对非亡灵/恶魔返回 True (防止双重推荐)
        return not isUndeadOrDemon, "target"
    end
end

function Module:CheckMeleeSpell(id)
    -- 基础判断：近战条件 (存活、距离、可用)
    if self:CheckMeleeConditions(id) then
        return true, "target"
    end
    return false
end

function Module:CheckConsecration()
    -- 1. 基础可用性判断
    if not self:IsSpellReady(48819) then return false end
    
    -- 2. 距离判断 (AOE技能，对齐10码参考)
    if not self:IsInRange(20271) or UnitIsDead("target") then return false end
    
    -- 3. 统一蓝量检查：40% 保底
    if self:GetUnitManaPercent("player") < 40 then return false end

    -- 获取核心技能冷却状态
    local dsCD = self:GetSpellCooldownLeft(53385)
    
    -- 4. 多目标 AOE 场景判断
    local numTargets = 1
    if Hekili and Hekili.State and Hekili.State.active_enemies then
        numTargets = Hekili.State.active_enemies
    end

    if numTargets > 2 then
        -- 群体：TTD > 5秒 且 神圣风暴在CD
        if self:GetTTD() > 5 and dsCD > 0 then
            return true, "player"
        end
    end

    -- 5. 单目标填充场景：核心打击技能和审判都在冷却
    local csCD = self:GetSpellCooldownLeft(35395)
    local exoCD = self:GetSpellCooldownLeft(48801)
    local judgeL_CD = self:GetSpellCooldownLeft(20271)
    local judgeW_CD = self:GetSpellCooldownLeft(53408)

    if csCD > 0 and dsCD > 0 and exoCD > 0 and judgeL_CD > 0 and judgeW_CD > 0 then
        return true, "player"
    end
    
    return false
end

function Module:CheckHolyWrath()
    -- 1. 基础可用性判断
    if not self:IsSpellReady(48817) then return false end
    
    -- 2. 检查神圣风暴 (53385) 是否在冷却中
    local dsCD = self:GetSpellCooldownLeft(53385)
    if dsCD <= 0 then return false end

    -- 3. 环境判断：存活、10码范围(审判参考)、敌对
    if self:IsInRange(20271) and not UnitIsDead("target") and UnitCanAttack("player", "target") then
        local type = UnitCreatureType("target")
        if type == "Undead" or type == "Demon" or type == "亡灵" or type == "恶魔" then
            return true, "player"
        end
    end
    return false
end

function Module:CheckDivineShield()
    if not self:IsSpellReady(642) then return false end
    -- 基础判断：生命值 < 20%
    if self:GetUnitHealthPercent("player") < 20 then
        if not self:HasDebuff("player", 25771) then return true, "player" end
    end
    return false
end

function Module:CheckHandOfSalvation()
    if not self:IsSpellReady(1038) then return false end
    -- 这里可以添加仇恨检查
    return false
end

function Module:CheckLionheart()
    -- 基础判断：Boss 战且 TTD > 10秒
    if not self:IsBoss("target") or self:GetTTD() < 10 then return false end
    
    local count = GetItemCount(20599)
    if count > 0 and IsUsableItem(20599) then
        local start, duration = GetItemCooldown(20599)
        if start == 0 then return true, "player" end
    end
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
        local _, _, _, _, _, expirationTime, _, _, _, sID = UnitBuff(unit, i)
        if not _ then break end
        if sID == spellID then return true end
    end
    return false
end

function Module:HasDebuff(unit, spellID)
    for i = 1, 40 do
        local _, _, _, _, _, expirationTime, _, _, _, sID = UnitDebuff(unit, i)
        if not _ then break end
        if sID == spellID then return true end
    end
    return false
end

function Module:IsSpellReady(id)
    local s, d = GetSpellCooldown(id)
    return (not s or s == 0 or (s + d - GetTime() <= 0))
end

function Module:IsLearned(name, id)
    return IsSpellKnown(id) or GetSpellInfo(name) ~= nil
end

function Module:InsertPaladinSkills()
    if not Hekili or not Hekili.DisplayPool then return end
    
    -- 更新 TTD 数据
    self:UpdateTTD()
    
    -- 检查整体开关
    if not HekiliHelper.DB or not HekiliHelper.DB.profile or not HekiliHelper.DB.profile.retPaladin or not HekiliHelper.DB.profile.retPaladin.enabled then
        return
    end

    for dispName, UI in pairs(Hekili.DisplayPool) do
        local lowerName = dispName:lower()
        if (lowerName == "primary" or lowerName == "aoe") and UI.Active and UI.alpha > 0 then
            local Queue = UI.Recommendations
            if not Queue then return end
            
            -- 清除旧标志，防止残留（不要设为 nil，防止 Hekili 渲染报错）
            for i = 1, 10 do
                if Queue[i] then 
                    Queue[i].isRetPaladinSkill = nil 
                end
            end

            local skillsFound = 0
            for _, skillDef in ipairs(self.SkillDefinitions) do
                if self:IsLearned(skillDef.displayName, skillDef.spellID) or (skillDef.actionName == "lionheart" and GetItemCount(20599) > 0) then
                    local should, target = skillDef.checkFunc(self)
                    if should and skillsFound < 4 then
                        skillsFound = skillsFound + 1
                        
                        local ability = Hekili.Class.abilities[skillDef.actionName]
                        if not ability then
                            local n, _, t
                            if skillDef.actionName == "lionheart" then
                                n, _, _, _, _, _, _, _, _, t = GetItemInfo(20599)
                            else
                                n, _, t = GetSpellInfo(skillDef.spellID)
                            end
                            
                            if n then
                                Hekili.Class.abilities[skillDef.actionName] = { 
                                    key = skillDef.actionName, name = n, texture = t, id = skillDef.spellID, cast = 0, gcd = "off" 
                                }
                                ability = Hekili.Class.abilities[skillDef.actionName]
                            end
                        end
                        
                        if ability then
                            Queue[skillsFound] = Queue[skillsFound] or {}
                            local slot = Queue[skillsFound]
                            slot.actionName = skillDef.actionName
                            slot.actionID = skillDef.spellID
                            slot.texture = ability.texture
                            slot.isRetPaladinSkill = true
                            slot.display = dispName
                            slot.time = 0
                            slot.exact_time = GetTime()
                            UI.NewRecommendations = true
                        end
                    end
                end
            end
        end
    end
end
