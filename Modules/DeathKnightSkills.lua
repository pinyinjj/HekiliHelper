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

-- 状态变量
Module.IsActive = false
Module.ContinuousOverrideActive = false
Module.CachedShouldShow = false  -- 缓存的shouldShow值，用于稳定判断
Module.ShowDelayStart = 0  -- 开始显示延迟的时间戳

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

-- 获取用户设置的显示图标数量（1-10）
function Module:GetNumIcons()
    local profile = Hekili.DB and Hekili.DB.profile
    if profile and profile.displays and profile.displays.Primary then
        return profile.displays.Primary.numIcons or 3
    end
    return 3  -- 默认值（适配1-10）
end

-- 持续覆盖函数：Hook UI 的 OnUpdate 实现每帧覆盖
function Module:StartContinuousOverride()
    local displays = Hekili.DisplayPool
    if not displays or not displays.Primary then
        C_Timer.After(0.1, function() Module:StartContinuousOverride() end)
        return
    end

    local UI = displays.Primary
    if self.ContinuousOverrideActive then return end
    self.ContinuousOverrideActive = true

    -- Hook UI 的 OnUpdate
    local originalOnUpdate = UI:GetScript('OnUpdate')
    UI:SetScript('OnUpdate', function(self, elapsed)
        if originalOnUpdate then
            originalOnUpdate(self, elapsed)
        end
        -- 每帧都执行强制插入
        Module:ForceInsertPestilence()
    end)
end

-- 模块初始化
function Module:Initialize()
    HekiliHelper:DebugPrint("[DK] ===== Initialize 开始 =====")

    if not Hekili then
        HekiliHelper:DebugPrint("[DK] Hekili不存在!")
        return false
    end
    HekiliHelper:DebugPrint("[DK] Hekili存在")

    -- 只对死亡骑士生效
    local _, class = UnitClass("player")
    HekiliHelper:DebugPrint("[DK] 玩家职业: " .. tostring(class))
    if class ~= "DEATHKNIGHT" then
        HekiliHelper:DebugPrint("[DK] 不是死亡骑士，跳过!")
        return true
    end
    HekiliHelper:DebugPrint("[DK] 是死亡骑士，继续...")

    -- 检查Hekili.Update是否存在
    if not Hekili.Update then
        HekiliHelper:DebugPrint("[DK] Hekili.Update不存在!")
        return false
    end
    HekiliHelper:DebugPrint("[DK] Hekili.Update存在，准备Hook...")

    -- 检查HookUtils.Wrap是否存在
    if not HekiliHelper.HookUtils.Wrap then
        HekiliHelper:DebugPrint("[DK] HookUtils.Wrap不存在!")
        return false
    end
    HekiliHelper:DebugPrint("[DK] HookUtils.Wrap存在")

    -- 使用HookUtils.Wrap + UI OnUpdate 持续覆盖
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        Module:ForceInsertPestilence()
        if not Module.ContinuousOverrideActive then
            Module:StartContinuousOverride()
        end
        return result
    end)

    if success then
        HekiliHelper:DebugPrint("[DK] ===== Hook成功，模块初始化完成 =====")
        return true
    else
        HekiliHelper:DebugPrint("[DK] HookUtils.Wrap失败!")
    end
    return false
end

-- TTD模块按需初始化（仅当传染功能启用时）
function Module:EnsureTTDInitialized()
    local TTD = HekiliHelper.TTD
    if TTD and TTD.Initialize and not TTD.initialized then
        TTD:Initialize()
        TTD.initialized = true
    end
end

-- 强制插入逻辑（用于每个Update周期后强制覆盖队列）
function Module:ForceInsertPestilence()
    -- 检查开关
    local db = HekiliHelper.DB.profile
    if not db.deathKnight or not db.deathKnight.enabled then
        if self.IsActive then
            self:RemovePestilence()
            self.IsActive = false
        end
        self.CachedShouldShow = false
        self.ShowDelayStart = 0
        return
    end

    -- 按需初始化TTD模块（仅当传染启用时）
    self:EnsureTTDInitialized()

    -- 检查是否应该显示
    local shouldShow = self:ShouldRecommendPestilence()
    local displays = Hekili.DisplayPool
    if not displays or not displays.Primary then
        return
    end

    local UI = displays.Primary
    if not UI.Recommendations then
        return
    end
    local Queue = UI.Recommendations

    -- 如果计算结果发生变化，更新缓存
    if shouldShow ~= self.CachedShouldShow then
        self.CachedShouldShow = shouldShow
        -- 当shouldShow变为true时，开始计时延迟
        if shouldShow then
            self.ShowDelayStart = GetTime()
        else
            self.ShowDelayStart = 0
        end
        return  -- 等待下一帧确认，避免单帧波动导致闪烁
    end

    -- 使用稳定的缓存值进行判断
    local stableShouldShow = self.CachedShouldShow

    -- 如果不应该显示但之前是活跃状态，需要移除
    if not stableShouldShow then
        if self.IsActive then
            -- 恢复原始推荐
            if Queue[1] and Queue[1].originalRecommendation then
                local original = Queue[1].originalRecommendation
                for k, v in pairs(Queue[1]) do Queue[1][k] = nil end
                for k, v in pairs(original) do Queue[1][k] = v end
            else
                Queue[1] = nil
            end
            UI.NewRecommendations = true
            self.IsActive = false
        end
        self.ShowDelayStart = 0
        return
    end

    -- 如果已经有传染在位置1，也认为是活跃状态
    if Queue[1] and Queue[1].isDeathKnightSkill and Queue[1].actionName == "pestilence" then
        self.IsActive = true
        self.ShowDelayStart = 0
        return
    end

    -- 检查延迟是否完成（0.2秒）
    local delayPassed = (GetTime() - self.ShowDelayStart) >= 0.2
    if not delayPassed then
        return
    end

    -- 准备插入图标
    local _, _, texture = GetSpellInfo(PESTILENCE_SPELL_ID)
    if not texture then
        return
    end

    -- 动态获取用户设置的显示数量
    local numIcons = self:GetNumIcons()

    -- 保存原始队列以便恢复
    local originalQueue = {}
    for i = 1, numIcons do
        if Queue[i] then
            originalQueue[i] = {}
            for k, v in pairs(Queue[i]) do
                originalQueue[i][k] = v
            end
        end
    end

    -- 将队列向后移动
    for i = numIcons, 2, -1 do
        Queue[i] = originalQueue[i - 1]
    end

    -- 在位置1插入传染
    Queue[1] = {}
    local slot = Queue[1]
    slot.index = 1
    slot.actionName = "pestilence"
    slot.actionID = PESTILENCE_SPELL_ID
    slot.texture = texture
    slot.isDeathKnightSkill = true
    slot.originalRecommendation = originalQueue[1]
    slot.time = 0
    slot.exact_time = GetTime()
    slot.delay = 0
    slot.display = "Primary"

    -- 注册虚拟技能
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
    self.IsActive = true
    self.LastShouldShow = shouldShow
end

-- 移除传染图标
function Module:RemovePestilence()
    local displays = Hekili.DisplayPool
    if not displays or not displays.Primary then return end

    local UI = displays.Primary
    local Queue = UI.Recommendations
    if not Queue then return end

    if Queue[1] and Queue[1].isDeathKnightSkill and Queue[1].actionName == "pestilence" then
        -- 恢复原始推荐
        if Queue[1].originalRecommendation then
            local original = Queue[1].originalRecommendation
            for k, v in pairs(Queue[1]) do Queue[1][k] = nil end
            for k, v in pairs(original) do Queue[1][k] = v end
        else
            Queue[1] = nil
        end

        UI.NewRecommendations = true
    end
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

    local targetExists = UnitExists("target")
    if not targetExists then
        return hasFF, ffTime, hasBP, bpTime
    end

    for i = 1, 40 do
        local name, _, _, _, _, expirationTime, unitCaster, _, _, spellId = UnitDebuff("target", i)
        if not name then
            break
        end

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
        local _, _, ready = GetRuneCooldown(i)
        local runeType = GetRuneType(i) -- 1: Blood, 2: Unholy, 3: Frost, 4: Death
        if ready and (runeType == 1 or runeType == 4) then
            readyCount = readyCount + 1
        end
    end
    return readyCount > 0
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
    -- 1. 基础配置快速失败（不检查冷却，因为图标应该提前显示）
    local db = HekiliHelper.DB.profile
    if not db.deathKnight or not db.deathKnight.enabled then
        return false
    end

    local TTD = HekiliHelper.TTD

    local isKnown = IsSpellKnown(PESTILENCE_SPELL_ID)
    local runeReady = self:IsBloodOrDeathRuneReady()

    if not (isKnown and runeReady) then
        return false
    end

    -- 2. 疾病状态与双病检查
    local hasFF, ffTime, hasBP, bpTime = self:GetTargetDiseaseStatus()
    if not (hasFF and hasBP) then
        return false
    end

    -- 3. 环境与TTD数据
    local noDiseaseCount, _, anyOtherHighTTD = self:GetPestilenceTargetInfo(15)
    local targetTTD = TTD:GetTTD("target") or 99

    -- 4. 判定核心逻辑
    local decision = false
    local isBoss = self:IsBoss()
    local armyReady = self:IsArmyReady()
    local refreshThreshold = (isBoss and armyReady) and 5.5 or 3.0

    -- 判定 A: 疾病同步
    if (anyOtherHighTTD or targetTTD > 4.5) and math.abs(ffTime - bpTime) > 3 then
        decision = true

    -- 判定 B: 3秒刷新规则
    elseif ffTime < 3.0 or bpTime < 3.0 then
        decision = true

    -- 判定 C: 群体扩散
    elseif anyOtherHighTTD and noDiseaseCount >= 1 then
        decision = true

    -- 判定 D: 单体刷新
    elseif anyOtherHighTTD then
        if ffTime < refreshThreshold or bpTime < refreshThreshold then
            decision = true
        end

    -- 判定 E: 仅当前目标高TTD
    elseif targetTTD > 4.5 then
        if ffTime < refreshThreshold or bpTime < refreshThreshold then
            decision = true
        end

    -- 判定 F: 兜底
    else
        if ffTime < refreshThreshold or bpTime < refreshThreshold then
            decision = true
        end
    end

    return decision
end

-- 插入逻辑
-- 兼容旧接口（已废弃，使用ForceInsertPestilence替代）
function Module:InsertDeathKnightSkills()
    self:ForceInsertPestilence()
end
