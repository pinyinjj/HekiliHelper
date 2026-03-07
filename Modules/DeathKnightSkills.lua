-- Modules/DeathKnightSkills.lua
-- 死亡骑士技能模块
-- 针对WLK版本的死亡骑士，提供传染（Pestilence）等技能的智能推荐

local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.DeathKnightSkills then
            HH.DeathKnightSkills = {}
        end
    end)
    return
end

if not HekiliHelper.DeathKnightSkills then
    HekiliHelper.DeathKnightSkills = {}
end

local Module = HekiliHelper.DeathKnightSkills

-- 技能ID定义
local PESTILENCE_SPELL_ID = 50842
local FROST_FEVER_ID = 55095
local BLOOD_PLAGUE_ID = 55078
local GLYPH_PESTILENCE_ID = 58620 -- 传染雕文：半径增加5码
local GLYPH_DISEASE_ID = 43334   -- 疾病雕文：传染刷新目标疾病

-- 用于防止闪烁的状态变量
Module.LastRecommendationTime = 0
Module.RecommendationLinger = 0.2 -- 推荐图标最少停留0.2秒

-- 模块初始化
function Module:Initialize()
    if not Hekili then return false end
    
    -- 只对死亡骑士生效
    local _, class = UnitClass("player")
    if class ~= "DEATHKNIGHT" then
        return true
    end

    HekiliHelper:DebugPrint("|cFF00FF00[DeathKnight]|r 开始Hook Hekili.Update...")
    
    -- 使用“保存与恢复”模式，参考萨满模块
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        -- 在Hekili生成推荐之前，先保存我们的技能，防止被清除
        local savedSkills = {}
        if Hekili and Hekili.DisplayPool then
            for dispName, UI in pairs(Hekili.DisplayPool) do
                if UI and UI.Recommendations then
                    local Queue = UI.Recommendations
                    savedSkills[dispName] = {}
                    for i = 1, 4 do
                        if Queue[i] and Queue[i].isDeathKnightSkill then
                            savedSkills[dispName][i] = {}
                            for k, v in pairs(Queue[i]) do
                                savedSkills[dispName][i][k] = v
                            end
                        end
                    end
                end
            end
        end
        
        -- 调用原函数生成推荐
        local result = oldFunc(self, ...)
        
        -- 在Hekili更新后立即尝试恢复并重新插入
        C_Timer.After(0.001, function()
            if Hekili and Hekili.DisplayPool then
                for dispName, saved in pairs(savedSkills) do
                    local UI = Hekili.DisplayPool[dispName]
                    if UI and UI.Recommendations then
                        local Queue = UI.Recommendations
                        for i, savedSlot in pairs(saved) do
                            if not Queue[i] or not Queue[i].isDeathKnightSkill then
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
            
            -- 执行核心逻辑
            Module:InsertDeathKnightSkills()
        end)
        
        return result
    end)
    
    if success then
        HekiliHelper:DebugPrint("|cFF00FF00[DeathKnight]|r 模块已初始化")
        return true
    end
    return false
end

-- 检查是否装备了传染雕文
function Module:HasPestilenceGlyph()
    local currentSpec = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
    for i = 1, 6 do
        local enabled, _, _, glyphSpell, _ = GetGlyphSocketInfo(i, currentSpec)
        if enabled and glyphSpell == GLYPH_PESTILENCE_ID then
            return true
        end
    end
    return false
end

-- 检查是否装备了疾病雕文
function Module:HasDiseaseGlyph()
    local currentSpec = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
    for i = 1, 6 do
        local enabled, _, _, glyphSpell, _ = GetGlyphSocketInfo(i, currentSpec)
        if enabled and glyphSpell == GLYPH_DISEASE_ID then
            return true
        end
    end
    return false
end

-- 检查当前目标是否患有疾病及其剩余时间
function Module:GetTargetDiseaseStatus()
    local hasFF, ffTime = false, 0
    local hasBP, bpTime = false, 0
    
    for i = 1, 40 do
        local name, _, _, _, _, expirationTime, unitCaster, _, _, spellId = UnitDebuff("target", i)
        if not name then break end
        
        if unitCaster == "player" then
            if spellId == FROST_FEVER_ID then
                hasFF = true
                ffTime = expirationTime > 0 and (expirationTime - GetTime()) or 99
            elseif spellId == BLOOD_PLAGUE_ID then
                hasBP = true
                bpTime = expirationTime > 0 and (expirationTime - GetTime()) or 99
            end
        end
    end
    
    local minTime = 0
    if hasFF and hasBP then
        minTime = math.min(ffTime, bpTime)
    elseif hasFF then
        minTime = ffTime
    elseif hasBP then
        minTime = bpTime
    end
    
    return (hasFF or hasBP), minTime
end

-- 检查是否有可用的鲜血符文或死亡符文
function Module:IsBloodOrDeathRuneReady()
    for i = 1, 6 do
        local start, duration, ready = GetRuneCooldown(i)
        local runeType = GetRuneType(i) -- 1: Blood, 2: Unholy, 3: Frost, 4: Death
        if ready and (runeType == 1 or runeType == 4) then
            return true
        end
    end
    return false
end

-- 检查单位是否患有玩家施放的疾病
function Module:UnitHasMyDiseases(unit)
    local hasFF, hasBP = false, false
    for i = 1, 40 do
        local name, _, _, _, _, _, unitCaster, _, _, spellId = UnitDebuff(unit, i)
        if not name then break end
        if unitCaster == "player" then
            if spellId == FROST_FEVER_ID then hasFF = true end
            if spellId == BLOOD_PLAGUE_ID then hasBP = true end
        end
    end
    return hasFF or hasBP
end

-- 判断是否为"真实"敌方目标
function Module:IsRealEnemy(unit)
    if not UnitExists(unit) or UnitIsDead(unit) or not UnitCanAttack("player", unit) then
        return false
    end
    local name = UnitName(unit)
    if not name then return false end
    if UnitCreatureType(unit) == "Totem" or UnitCreatureType(unit) == "Non-combat Pet" or UnitCreatureType(unit) == "Critter" then
        return false
    end
    if name:find("Totem") or name:find("图腾") then
        return false
    end
    return true
end

-- 统计范围内没有疾病的目标
function Module:CountEnemiesWithoutDiseasesInRange(range)
    local RC = LibStub("LibRangeCheck-2.0")
    if not RC then return 0 end
    
    local count = 0
    local checkedGUIDs = {}
    local foundInfo = {} -- 用于存储调试信息
    
    local unitsToCheck = {"target", "focus"}
    for i = 1, 5 do table.insert(unitsToCheck, "boss"..i) end
    
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local nameplates = C_NamePlate.GetNamePlates()
        if nameplates then
            for _, frame in ipairs(nameplates) do
                local unit = frame.namePlateUnitToken
                if unit then table.insert(unitsToCheck, unit) end
            end
        end
    end
    
    for _, unit in ipairs(unitsToCheck) do
        if self:IsRealEnemy(unit) then
            local guid = UnitGUID(unit)
            if guid and not checkedGUIDs[guid] then
                checkedGUIDs[guid] = true
                local _, maxRange = RC:GetRange(unit)
                
                -- 只要在检测范围内，就收集信息进行打印
                if maxRange and maxRange <= range then
                    local hasDiseases = self:UnitHasMyDiseases(unit)
                    local name = UnitName(unit)
                    
                    -- 格式化信息：名称(距离, 状态)
                    local statusStr = hasDiseases and "|cFFFF0000有病|r" or "|cFF00FF00无病|r"
                    table.insert(foundInfo, string.format("%s(%d码, %s)", name, maxRange, statusStr))
                    
                    if not hasDiseases then
                        count = count + 1
                    end
                end
            end
        end
    end
    
    -- 如果发现了任何目标，打印详细信息
    if #foundInfo > 0 then
        HekiliHelper:DebugPrint(string.format("|cFF00FF00[DK扫描]|r 15码内发现%d个敌对目标: %s", #foundInfo, table.concat(foundInfo, ", ")))
    end
    
    return count
end

-- 判断逻辑核心
function Module:ShouldRecommendPestilence()
    -- 基础检查
    local db = HekiliHelper.DB.profile
    if not db.deathKnight or not db.deathKnight.enabled then return false end
    
    -- 锁定逻辑：如果刚刚推荐过，在极短时间内强制返回true，防止闪烁
    local now = GetTime()
    if now - self.LastRecommendationTime < self.RecommendationLinger then
        return true
    end

    if not IsSpellKnown(PESTILENCE_SPELL_ID) then return false end
    local start, duration = GetSpellCooldown(PESTILENCE_SPELL_ID)
    if start and start > 0 and duration > 1.5 then return false end

    local hasDiseases, minDuration = self:GetTargetDiseaseStatus()
    if not hasDiseases then return false end
    
    local decision = false
    -- 条件1：群体感染
    if self:HasPestilenceGlyph() and self:IsBloodOrDeathRuneReady() then
        if self:CountEnemiesWithoutDiseasesInRange(15) > 2 then
            decision = true
        end
    end
    
    -- 条件2：刷新疾病
    if not decision and self:HasDiseaseGlyph() and minDuration < 3 and self:IsBloodOrDeathRuneReady() then
        decision = true
    end
    
    if decision then
        self.LastRecommendationTime = now
    end
    
    return decision
end

-- 插入逻辑
function Module:InsertDeathKnightSkills()
    if not Hekili or not Hekili.DisplayPool then return end
    
    local shouldShow = self:ShouldRecommendPestilence()
    
    for dispName, UI in pairs(Hekili.DisplayPool) do
        if dispName == "Primary" or dispName == "AOE" then
            if shouldShow then
                self:InsertSkillForDisplay(dispName, UI)
            else
                if UI.Recommendations then
                    for i = 1, 4 do
                        if UI.Recommendations[i] and UI.Recommendations[i].isDeathKnightSkill then
                            self:RemoveSkillFromQueue(UI.Recommendations, UI, i)
                        end
                    end
                end
            end
        end
    end
end

function Module:RemoveSkillFromQueue(Queue, UI, slotIndex)
    local slot = Queue[slotIndex]
    if slot.originalRecommendation then
        local original = slot.originalRecommendation
        for k, v in pairs(slot) do slot[k] = nil end
        for k, v in pairs(original) do slot[k] = v end
    else
        slot.actionName = nil
        slot.actionID = nil
        slot.texture = nil
        slot.isDeathKnightSkill = nil
    end
    UI.NewRecommendations = true
end

function Module:InsertSkillForDisplay(dispName, UI)
    if not UI or not UI.Recommendations then return end
    local Queue = UI.Recommendations
    
    -- 检查是否已经在位置1且正确
    if Queue[1] and Queue[1].actionName == "pestilence" and Queue[1].isDeathKnightSkill then
        return
    end

    local insertIndex = 1
    local originalSlot = nil
    if Queue[insertIndex] and Queue[insertIndex].actionName and not Queue[insertIndex].isDeathKnightSkill then
        originalSlot = {}
        for k, v in pairs(Queue[insertIndex]) do originalSlot[k] = v end
    end
    
    local _, _, texture = GetSpellInfo(PESTILENCE_SPELL_ID)
    Queue[insertIndex] = Queue[insertIndex] or {}
    local slot = Queue[insertIndex]
    
    slot.index = insertIndex
    slot.actionName = "pestilence"
    slot.actionID = PESTILENCE_SPELL_ID
    slot.texture = texture
    slot.time = 0
    slot.exact_time = GetTime()
    slot.delay = 0
    slot.since = 0
    slot.display = dispName
    slot.isDeathKnightSkill = true
    slot.originalRecommendation = originalSlot
    
    if not Hekili.Class.abilities["pestilence"] then
        Hekili.Class.abilities["pestilence"] = {
            key = "pestilence",
            name = "传染",
            texture = texture,
            id = PESTILENCE_SPELL_ID,
            cast = 0,
            gcd = "spell",
        }
    end
    
    UI.NewRecommendations = true
end
