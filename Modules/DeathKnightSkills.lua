-- Modules/DeathKnightSkills.lua
-- 死亡骑士技能模块
-- 采用“UI覆盖逻辑”：在 Hekili 主图标上叠加一层图标，不修改原生队列，彻底解决闪烁和逻辑冲突。

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
local GLYPH_PESTILENCE_ID = 58647
local GLYPH_DISEASE_ID = 58680

-- 状态变量
Module.IsActive = false
Module.TTDInitialized = false
Module.OverlayFrame = nil

-- ===== TTD 内置实现 =====
local ttdUnitData = {}
local function UpdateTTDUnitData(unit)
    if not UnitExists(unit) or UnitIsDead(unit) or UnitIsFriend("player", unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local now = GetTime()
    local data = ttdUnitData[guid]
    if not data then
        data = {guid = guid, samples = {}, ptr = 1, count = 0, lastUpdate = 0}
        ttdUnitData[guid] = data
    end
    if now - data.lastUpdate < 0.2 then return end
    local currentHealth = UnitHealth(unit)
    data.samples[data.ptr] = {time = now, health = currentHealth}
    data.ptr = (data.ptr % 15) + 1
    data.count = math.min(data.count + 1, 15)
    data.lastUpdate = now
end

function Module:GetTTD(unit)
    if not UnitExists(unit) or UnitIsDead(unit) then return nil end
    local guid = UnitGUID(unit)
    local data = ttdUnitData[guid]
    if not data or data.count < 2 then 
        UpdateTTDUnitData(unit)
        return nil 
    end
    local first = data.samples[data.count == 15 and data.ptr or 1]
    local last = data.samples[data.ptr == 1 and 15 or data.ptr - 1]
    local timeDiff = last.time - first.time
    local healthDiff = first.health - last.health
    if timeDiff < 1.5 or healthDiff <= 0 then return nil end
    return UnitHealth(unit) / (healthDiff / timeDiff)
end

function Module:InitializeTTDEvents()
    if self.TTDInitialized then return end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            local unit = ...
            if unit then UpdateTTDUnitData(unit) end
        elseif event == "PLAYER_TARGET_CHANGED" then
            UpdateTTDUnitData("target")
        elseif event == "PLAYER_REGEN_ENABLED" then
            ttdUnitData = {}
        end
    end)
    f:RegisterEvent("UNIT_HEALTH")
    f:RegisterEvent("UNIT_MAXHEALTH")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.TTDInitialized = true
end

-- ===== 辅助判定函数 =====

function Module:GetTargetDiseaseStatus()
    local hasFF, ffTime, hasBP, bpTime = false, 0, false, 0
    for i = 1, 40 do
        local _, _, _, _, _, expirationTime, unitCaster, _, _, spellId = UnitDebuff("target", i)
        if not spellId then break end
        if unitCaster == "player" then
            local timeLeft = expirationTime > 0 and (expirationTime - GetTime()) or 99
            if spellId == FROST_FEVER_ID then hasFF, ffTime = true, timeLeft
            elseif spellId == BLOOD_PLAGUE_ID then hasBP, bpTime = true, timeLeft end
        end
    end
    return hasFF, ffTime, hasBP, bpTime
end

function Module:UnitHasMyDiseases(unit)
    local hasFF, hasBP = false, false
    for i = 1, 40 do
        local _, _, _, _, _, _, unitCaster, _, _, spellId = UnitDebuff(unit, i)
        if not spellId then break end
        if unitCaster == "player" then
            if spellId == FROST_FEVER_ID then hasFF = true
            elseif spellId == BLOOD_PLAGUE_ID then hasBP = true end
        end
    end
    return hasFF and hasBP
end

function Module:IsBloodOrDeathRuneReady()
    for i = 1, 6 do
        local _, _, ready = GetRuneCooldown(i)
        local runeType = GetRuneType(i)
        if ready and (runeType == 1 or runeType == 4) then return true end
    end
    return false
end

-- ===== UI 覆盖层实现 =====

function Module:CreateOverlay()
    if self.OverlayFrame then return self.OverlayFrame end
    local parent = _G["HekiliDisplayPrimary"] and _G["HekiliDisplayPrimary"].Buttons and _G["HekiliDisplayPrimary"].Buttons[1]
    if not parent then return nil end

    local f = CreateFrame("Frame", "HekiliHelperPestilenceOverlay", parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 50)
    f.texture = f:CreateTexture(nil, "OVERLAY")
    f.texture:SetAllPoints(f)
    
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(PESTILENCE_SPELL_ID) or select(3, GetSpellInfo(PESTILENCE_SPELL_ID))
    f.texture:SetTexture(icon)

    -- 发光效果
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, 3)
    f.glow:SetColorTexture(0, 1, 0, 0.4)

    f:Hide()
    self.OverlayFrame = f
    return f
end

function Module:Initialize()
    HekiliHelper:DebugPrint("[DK] ===== Initialize (Overlay模式) =====")
    local _, class = UnitClass("player")
    if class ~= "DEATHKNIGHT" then return true end

    HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        Module:ProcessPestilenceOverlay()
        return result
    end)
    return true
end

function Module:ProcessPestilenceOverlay()
    self:InitializeTTDEvents()
    
    -- 1. 获取判定结果
    local shouldShow, reason = self:ShouldRecommendPestilence()
    
    -- 2. 状态检查：如果状态没有变化，且已经初始化过，则直接返回
    if shouldShow == self.IsActive and self.OverlayFrame then
        -- 如果处于激活状态，额外确保一次父级可见性（防止被 Hekili 意外隐藏）
        if shouldShow then
            local parent = self.OverlayFrame:GetParent()
            if parent and not parent:IsShown() then parent:Show() end
        end
        return 
    end

    -- 3. 获取或创建覆盖层
    local overlay = self:CreateOverlay()
    if not overlay then return end

    -- 4. 执行状态切换
    if shouldShow then
        -- 进入激活状态
        self.LastReason = reason -- 记录触发原因
        HekiliHelper:DebugPrint(string.format("|cFF00FF00[DK] 开始渲染传染:|r %s", reason or "未知"))
        
        -- 确保父级可见
        local parent = overlay:GetParent()
        if parent then
            parent:SetAlpha(1)
            parent:Show()
        end
        
        overlay:Show()
        self.IsActive = true
    else
        -- 进入熄灭状态
        if self.IsActive then
            HekiliHelper:DebugPrint(string.format("|cFFFF0000[DK] 停止渲染传染:|r (触发原因: %s)", self.LastReason or "判定失效"))
        end
        overlay:Hide()
        self.IsActive = false
        self.LastReason = nil
    end
end

function Module:ShouldRecommendPestilence()
    if not IsSpellKnown(PESTILENCE_SPELL_ID) then return false end
    if not self:IsBloodOrDeathRuneReady() then return false end

    -- 1. 距离检查
    local RC = LibStub("LibRangeCheck-2.0")
    if RC then
        local _, maxRange = RC:GetRange("target")
        if maxRange and maxRange > 3 then return false end
    end

    -- 2. 获取双病状态
    local hasFF, ffTime, hasBP, bpTime = self:GetTargetDiseaseStatus()

    -- 3. 核心判定 A: 刷新逻辑 (优先级最高，只要有一个不满3秒且双病都在就刷新)
    if hasFF and hasBP then
        if ffTime < 3.0 or bpTime < 3.0 then
            return true, string.format("刷新-时间不足: FF=%.1f BP=%.1f", ffTime, bpTime)
        end
    end

    -- 4. 核心判定 B: 扩散逻辑
    if hasFF and hasBP then -- 必须主目标有病才能扩散
        local noDiseaseCount = 0
        local anyOtherHighTTD = false
        local targetGUID = UnitGUID("target")
        local unitsToCheck = {"target", "focus", "mouseover"}
        for i = 1, 40 do table.insert(unitsToCheck, "nameplate"..i) end
        
        local checked = {}
        for _, unit in ipairs(unitsToCheck) do
            if UnitExists(unit) and not UnitIsDead(unit) and UnitCanAttack("player", unit) then
                local guid = UnitGUID(unit)
                if guid and not checked[guid] then
                    checked[guid] = true
                    local _, maxRange = RC:GetRange(unit)
                    if (not maxRange) or (maxRange <= 8) then
                        if guid ~= targetGUID then
                            local healthPct = (UnitHealthMax(unit) > 0) and (UnitHealth(unit) / UnitHealthMax(unit) * 100) or 0
                            local ttd = self:GetTTD(unit) or (healthPct > 95 and 99 or 0)
                            if ttd > 4.5 then anyOtherHighTTD = true end
                            if not self:UnitHasMyDiseases(unit) then noDiseaseCount = noDiseaseCount + 1 end
                        end
                    end
                end
            end
        end

        if noDiseaseCount >= 1 then
            return true, string.format("扩散-发现目标: 无病数=%d", noDiseaseCount)
        end

        -- 核心判定 C: 高 TTD 提前刷新
        local isBoss = (UnitLevel("target") == -1 or UnitClassification("target") == "worldboss")
        local refreshThreshold = (isBoss and IsSpellKnown(ARMY_OF_THE_DEAD_ID)) and 5.5 or 3.0
        if anyOtherHighTTD and (ffTime < refreshThreshold or bpTime < refreshThreshold) then
            return true, string.format("刷新-提前量: 阈值=%.1f", refreshThreshold)
        end
    end

    return false
end

-- 兼容性占位
function Module:ForceInsertPestilence() end
function Module:InsertDeathKnightSkills() end
