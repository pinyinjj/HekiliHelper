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
Module.TTDInitialized = false  -- TTD事件是否已注册
Module.LastEnvTriggerTime = 0   -- 最近一次环境判定(扩散)触发的时间

-- ===== TTD (Time To Die) 内置实现 =====
-- TTD配置常量
local TTD_MAX_SAMPLES = 15       -- 样本数
local TTD_SAMPLE_THROTTLE = 0.2  -- 采样节流（秒）
local TTD_MIN_TIME_FOR_TTD = 1.5 -- 开始计算所需的最小观测时间

-- TTD内部数据
local ttdUnitData = {}
local ttdFrame = nil

-- TTD：更新单位数据
local function UpdateTTDUnitData(unit)
    if not UnitExists(unit) or UnitIsDead(unit) or UnitIsFriend("player", unit) then
        return
    end

    local guid = UnitGUID(unit)
    if not guid then return end

    local now = GetTime()
    local data = ttdUnitData[guid]

    -- 初始化新单位数据
    if not data then
        data = {
            guid = guid,
            samples = {},
            ptr = 1,
            count = 0,
            lastUpdate = 0
        }
        ttdUnitData[guid] = data
    end

    -- 节流检查
    if now - data.lastUpdate < TTD_SAMPLE_THROTTLE then
        return
    end

    local currentHealth = UnitHealth(unit)

    local lastIdx = data.ptr - 1
    if lastIdx < 1 then lastIdx = TTD_MAX_SAMPLES end

    if data.count == 0 or data.samples[lastIdx].health ~= currentHealth then
        data.samples[data.ptr] = {
            time = now,
            health = currentHealth
        }

        data.ptr = (data.ptr % TTD_MAX_SAMPLES) + 1
        data.count = math.min(data.count + 1, TTD_MAX_SAMPLES)
        data.lastUpdate = now
    end
end

-- TTD：获取TTD（秒）
function Module:GetTTD(unit)
    if not UnitExists(unit) or UnitIsDead(unit) then
        return nil
    end

    local guid = UnitGUID(unit)
    local data = ttdUnitData[guid]

    if not data then
        UpdateTTDUnitData(unit)
        return nil
    end

    if data.count < 2 then
        return nil
    end

    local firstIdx = 1
    if data.count == TTD_MAX_SAMPLES then
        firstIdx = data.ptr
    end

    local lastIdx = data.ptr - 1
    if lastIdx < 1 then lastIdx = TTD_MAX_SAMPLES end

    local first = data.samples[firstIdx]
    local last = data.samples[lastIdx]

    if not first or not last then
        return nil
    end

    local timeDiff = last.time - first.time
    local healthDiff = first.health - last.health

    if timeDiff < TTD_MIN_TIME_FOR_TTD or healthDiff <= 0 then
        return nil
    end

    local dps = healthDiff / timeDiff
    local currentHealth = UnitHealth(unit)
    local ttd = currentHealth / dps

    if ttd > 3600 then return nil end

    return ttd
end

-- TTD：初始化事件监听
function Module:InitializeTTDEvents()
    if self.TTDInitialized then return end

    ttdFrame = CreateFrame("Frame")
    ttdFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            local unit = ...
            if unit then UpdateTTDUnitData(unit) end
        elseif event == "PLAYER_TARGET_CHANGED" then
            UpdateTTDUnitData("target")
        elseif event == "PLAYER_REGEN_ENABLED" then
            ttdUnitData = {}
        end
    end)

    ttdFrame:RegisterEvent("UNIT_HEALTH")
    ttdFrame:RegisterEvent("UNIT_MAXHEALTH")
    ttdFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    ttdFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    self.TTDInitialized = true
end

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

-- 兼容性获取法术信息
local function GetSpellTexture(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    local _, _, texture = GetSpellInfo(spellID)
    return texture
end

-- 强制插入逻辑（用于每个Update周期后强制覆盖队列）
function Module:ForceInsertPestilence()
    -- 初始化TTD事件
    self:InitializeTTDEvents()

    local displays = Hekili.DisplayPool
    if not displays then return end

    -- 兼容性检查：支持 Primary 或 primary
    local UI = displays.Primary or displays.primary
    if not UI then
        return
    end

    if not UI.Recommendations then
        return
    end

    -- 检查是否应该显示
    local shouldShow = self:ShouldRecommendPestilence()

    local Queue = UI.Recommendations

    -- 如果不应该显示但之前是活跃状态，需要移除
    if not shouldShow then
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
        return
    end

    -- 如果已经有传染在位置1，只需维持状态，不再执行后续移动队列和重复插入的操作
    if Queue[1] and Queue[1].isDeathKnightSkill and Queue[1].actionName == "pestilence" then
        self.IsActive = true
        return
    end

    -- 准备插入图标
    local texture = GetSpellTexture(PESTILENCE_SPELL_ID)
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

-- 检查单位是否患有玩家施放的所有疾病（双病齐全）
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
    -- 修改：必须两种疾病齐全才算“有病”，否则传染能补齐缺失的疾病
    return hasFF and hasBP
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
    if not RC then return 0, 0, false end

    local noDiseaseCount = 0
    local othersWithHighTTDCount = 0
    local anyOtherHighTTD = false
    local checkedGUIDs = {}

    local targetGUID = UnitGUID("target")
    local unitsToCheck = {"target", "focus", "mouseover"}
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
                
                -- 获取范围。如果获取失败，默认为在范围内以保证推荐灵敏度
                local minRange, maxRange = RC:GetRange(unit)
                local inRange = (not maxRange) or (maxRange <= range)

                if inRange then
                    local ttd = self:GetTTD(unit) or 99
                    local hasDiseases = self:UnitHasMyDiseases(unit)

                    if guid ~= targetGUID then
                        -- 只有非当前目标才统计 TTD
                        if ttd > 4.5 then
                            anyOtherHighTTD = true
                            othersWithHighTTDCount = othersWithHighTTDCount + 1
                        end
                        
                        -- 只有非当前目标才统计无病数量
                        if not hasDiseases then
                            noDiseaseCount = noDiseaseCount + 1
                        end
                    end
                end
            end
        end
    end

    return noDiseaseCount, othersWithHighTTDCount, anyOtherHighTTD
end

-- 判断逻辑核心
function Module:ShouldRecommendPestilence()
    -- 1. 基础检查
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
    local range = self:HasPestilenceGlyph() and 15 or 10
    local noDiseaseCount, othersWithHighTTDCount, anyOtherHighTTD = self:GetPestilenceTargetInfo(range)
    local targetTTD = self:GetTTD("target") or 99

    -- 4. 判定核心逻辑
    local decision = false
    local isBoss = self:IsBoss()
    local armyReady = self:IsArmyReady()
    local refreshThreshold = (isBoss and armyReady) and 5.5 or 3.0

    -- 判定 B: 3秒刷新规则 (优先级最高)
    if ffTime < 3.0 or bpTime < 3.0 then
        decision = true
        HekiliHelper:DebugPrint(string.format("[DK] 刷新-时间不足: FF=%.1f BP=%.1f", ffTime, bpTime))

    -- 判定 C: 群体扩散 (只要有无病目标且不是快死的怪)
    elseif noDiseaseCount >= 1 then
        decision = true
        self.LastEnvTriggerTime = GetTime()
        HekiliHelper:DebugPrint(string.format("[DK] 扩散-发现目标: 无病数=%d 范围=%d", noDiseaseCount, range))

    -- 判定 D: 单体刷新 (疾病雕文)
    elseif anyOtherHighTTD then
        if ffTime < refreshThreshold or bpTime < refreshThreshold then
            decision = true
            HekiliHelper:DebugPrint(string.format("[DK] 刷新-疾病雕文: 阈值=%.1f FF=%.1f BP=%.1f", refreshThreshold, ffTime, bpTime))
        end

    -- 判定 E: 仅当前目标高TTD
    elseif targetTTD > 4.5 then
        if ffTime < refreshThreshold or bpTime < refreshThreshold then
            decision = true
            HekiliHelper:DebugPrint(string.format("[DK] 刷新-当前高TTD: 阈值=%.1f FF=%.1f BP=%.1f", refreshThreshold, ffTime, bpTime))
        end
    end

    -- 稳定性平滑
    if not decision and (GetTime() - self.LastEnvTriggerTime) < 0.5 then
        if hasFF and hasBP and runeReady then
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
