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
local ARMY_OF_THE_DEAD_ID = 42650
-- 修正：使用用户实际装备的雕文ID
local GLYPH_PESTILENCE_ID = 58647 -- 传染雕文效果ID
local GLYPH_DISEASE_ID = 58680    -- 疾病雕文效果ID (用户提供的 63334 也是，我们在Check里同时支持)

-- 用于防止闪烁的状态变量
Module.LastRecommendationTime = 0
Module.LastPrintTime = 0
Module.LastReason = ""
Module.RecommendationLinger = 0.2 -- 推荐图标最少停留0.2秒

-- 辅助函数：判断是否为Boss
function Module:IsBoss()
    if not UnitExists("target") then return false end
    local level = UnitLevel("target")
    local classification = UnitClassification("target")
    return level == -1 or classification == "worldboss" or classification == "elite"
end

-- 辅助函数：王者大军是否可用
function Module:IsArmyReady()
    if not IsSpellKnown(ARMY_OF_THE_DEAD_ID) then return false end
    local start, duration = GetSpellCooldown(ARMY_OF_THE_DEAD_ID)
    return (not start or start == 0 or duration <= 1.5)
end

-- 辅助函数：打印并检查雕文
function Module:CheckAllGlyphs()
    local currentSpec = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
    local found = {}
    local hasPes, hasDis = false, false
    
    for i = 1, 6 do
        local enabled, _, _, glyphSpellID, _ = GetGlyphSocketInfo(i, currentSpec)
        if enabled and glyphSpellID then
            table.insert(found, glyphSpellID)
            if glyphSpellID == GLYPH_PESTILENCE_ID then hasPes = true end
            -- 疾病雕文支持两个可能的ID
            if glyphSpellID == 58680 or glyphSpellID == 63334 then hasDis = true end
        end
    end
    
    return hasPes, hasDis, found
end

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
    local hasPes, _, _ = self:CheckAllGlyphs()
    return hasPes
end

-- 检查是否装备了疾病雕文
function Module:HasDiseaseGlyph()
    local _, hasDis, _ = self:CheckAllGlyphs()
    return hasDis
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
    
    return hasFF, ffTime, hasBP, bpTime
end

-- 检查是否有可用的鲜血符文或死亡符文
function Module:IsBloodOrDeathRuneReady()
    local readyCount = 0
    for i = 1, 6 do
        local start, duration, ready = GetRuneCooldown(i)
        local runeType = GetRuneType(i) -- 1: Blood, 2: Unholy, 3: Frost, 4: Death
        if ready and (runeType == 1 or runeType == 4) then
            readyCount = readyCount + 1
        end
    end
    return readyCount > 0, readyCount
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

-- 统计范围内没有疾病的目标，并检查其 TTD
function Module:GetPestilenceTargetInfo(range)
    local RC = LibStub("LibRangeCheck-2.0")
    local TTD = HekiliHelper.TTD
    if not RC or not TTD then return 0, 0, false end
    
    local noDiseaseCount = 0
    local othersWithHighTTDCount = 0
    local anyOtherHighTTD = false
    local checkedGUIDs = {}
    
    local targetGUID = UnitGUID("target")
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
                
                if maxRange and maxRange <= range then
                    local ttd = TTD:GetTTD(unit) or 99 -- 无法计算时默认为长寿命
                    local hasDiseases = self:UnitHasMyDiseases(unit)
                    
                    if guid ~= targetGUID then
                        if ttd > 4.5 then
                            anyOtherHighTTD = true
                            othersWithHighTTDCount = othersWithHighTTDCount + 1
                        end
                    end
                    
                    if not hasDiseases then
                        noDiseaseCount = noDiseaseCount + 1
                    end
                end
            end
        end
    end
    
    return noDiseaseCount, othersWithHighTTDCount, anyOtherHighTTD
end

-- 判断逻辑核心
function Module:ShouldRecommendPestilence()
    -- 基础检查
    local db = HekiliHelper.DB.profile
    if not db.deathKnight or not db.deathKnight.enabled then return false end
    
    local now = GetTime()
    local TTD = HekiliHelper.TTD
    
    -- 1. 前置状态获取
    local isKnown = IsSpellKnown(PESTILENCE_SPELL_ID)
    local start, duration = GetSpellCooldown(PESTILENCE_SPELL_ID)
    local cdLeft = (start and start > 0) and (start + duration - now) or 0
    local hasPesGlyph, hasDisGlyph, _ = self:CheckAllGlyphs()
    local runeReady, _ = self:IsBloodOrDeathRuneReady()
    
    -- 2. 核心逻辑判断
    local decision = false
    local reason = ""
    
    if isKnown and cdLeft <= 1.5 and runeReady then
        local noDiseaseCount, othersHighTTDCount, anyOtherHighTTD = self:GetPestilenceTargetInfo(15)
        local hasFF, ffTime, hasBP, bpTime = self:GetTargetDiseaseStatus()
        local targetTTD = TTD:GetTTD("target") or 99
        
        -- 计算当前刷新阈值
        local refreshThreshold = 3.0
        if self:IsBoss() and self:IsArmyReady() then
            refreshThreshold = 5.5
        end
        
        -- 核心逻辑：必须双病齐全
        if hasFF and hasBP then
            -- TTD 判断核心规则
            if anyOtherHighTTD then
                -- 规则 A: 15码内有长寿命目标 (TTD > 4.5s)
                
                -- 情况 1: 群体扩散 (传染雕文)
                if hasPesGlyph and noDiseaseCount > 0 then
                    decision = true
                    reason = string.format("扩散: 15码内发现%d个高TTD目标且有%d个无病目标", othersHighTTDCount, noDiseaseCount)
                end
                
                -- 情况 2: 单体刷新 (疾病雕文)
                if not decision and hasDisGlyph and ffTime < refreshThreshold and bpTime < refreshThreshold then
                    decision = true
                    reason = string.format("刷新: 当前目标双病即将到期(FF:%.1fs, BP:%.1fs)", ffTime, bpTime)
                end
            else
                -- 规则 B: 15码内所有其他目标 TTD 都很短 (< 4.5s)
                -- 即使当前目标符合刷新条件，如果大家都要死了，也不推荐传染
                if targetTTD > 4.5 then
                    -- 仅在当前目标还能活很久，且没有其他目标可扩散时，考虑纯单体刷新
                    if hasDisGlyph and ffTime < refreshThreshold and bpTime < refreshThreshold then
                        decision = true
                        reason = string.format("纯单体刷新: 仅当前目标高TTD(%.1fs)", targetTTD)
                    end
                else
                    -- 当前目标和其他目标 TTD 都 < 4.5s -> 彻底放弃传染
                    -- decision = false
                end
            end
        end
    end
    
    -- 3. 防闪烁延迟处理
    if not decision and (now - self.LastRecommendationTime < self.RecommendationLinger) then
        return true
    end
    
    -- 4. 打印与状态更新
    if decision then
        self.LastRecommendationTime = now
        
        if reason ~= self.LastReason or (now - self.LastPrintTime > 1.0) then
            HekiliHelper:DebugPrint(string.format("|cFF00FF00[DK逻辑]|r %s", reason))
            self.LastReason = reason
            self.LastPrintTime = now
        end
    else
        if self.LastReason ~= "" then
            self.LastReason = ""
        end
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
