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
Module.LastReason = nil
Module.LastDiagnosticTime = 0 -- 诊断日志节流

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
        local name, _, _, _, _, expirationTime, unitCaster, _, _, spellId = UnitDebuff("target", i)
        if not name then break end -- 修复：使用 name 判定循环结束
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
        local name, _, _, _, _, _, unitCaster, _, _, spellId = UnitDebuff(unit, i)
        if not name then break end
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

function Module:GetHekiliPrimaryButton()
    if not Hekili or not Hekili.DisplayPool then return nil end
    local displays = Hekili.DisplayPool
    
    -- 1. 优先尝试 Primary
    local UI = displays.Primary or displays.primary
    if UI and UI.Buttons and UI.Buttons[1] then return UI.Buttons[1] end
    
    -- 2. 遍历所有显示寻找第一个有效的
    for _, disp in pairs(displays) do
        if type(disp) == "table" and disp.Buttons and disp.Buttons[1] then
            return disp.Buttons[1]
        end
    end
    
    return _G["HekiliDisplayPrimary"] and _G["HekiliDisplayPrimary"].Buttons and _G["HekiliDisplayPrimary"].Buttons[1]
end

function Module:CreateOverlay()
    if self.OverlayFrame then return self.OverlayFrame end
    
    local parent = self:GetHekiliPrimaryButton()
    if not parent then return nil end

    local size = 50
    if Hekili and Hekili.DB and Hekili.DB.profile and Hekili.DB.profile.displays then
        -- 尝试从配置中获取第一个显示的大小
        for _, cfg in pairs(Hekili.DB.profile.displays) do
            if cfg.primaryIconSize or cfg.buttonSize then
                size = cfg.primaryIconSize or cfg.buttonSize
                break
            end
        end
    end

    local f = CreateFrame("Frame", "HekiliHelperPestilenceOverlay", parent)
    f:SetSize(size, size)
    f:SetPoint("CENTER", parent, "CENTER")
    f:SetFrameStrata("TOOLTIP") -- 显式设为最高层级
    f:SetFrameLevel(9000)      -- 使用极高的绝对层级压过数字
    
    f.texture = f:CreateTexture(nil, "OVERLAY")
    f.texture:SetAllPoints(f)
    f.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(PESTILENCE_SPELL_ID) or select(3, GetSpellInfo(PESTILENCE_SPELL_ID))
    f.texture:SetTexture(icon)

    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.glow:SetColorTexture(0, 1, 0, 0.5)

    f:Hide()
    self.OverlayFrame = f
    return f
end

function Module:Initialize()
    HekiliHelper:DebugPrint("[DK] ===== Initialize (Overlay模式) 开始 =====")
    
    if not Hekili or not Hekili.Update then
        C_Timer.After(1.0, function() Module:Initialize() end)
        return false
    end

    local _, class = UnitClass("player")
    if class ~= "DEATHKNIGHT" then return true end

    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        Module:ProcessPestilenceOverlay()
        return result
    end)

    if success then
        HekiliHelper:DebugPrint("[DK] ===== Hook成功，覆盖模式已激活 =====")
    end
    
    return success
end

function Module:ProcessPestilenceOverlay()
    self:InitializeTTDEvents()
    
    local shouldShow, reason, diagnostics = self:ShouldRecommendPestilence()
    local overlay = self:CreateOverlay()
    
    if shouldShow then
        if not overlay then return end

        if not self.IsActive then
            self.LastReason = reason
            HekiliHelper:DebugPrint(string.format("|cFF00FF00[DK] 开始渲染传染:|r %s", reason or "未知"))
            self.IsActive = true
        end
        
        overlay:Show()
        local parent = overlay:GetParent()
        if parent then
            if not parent:IsShown() then parent:Show() end
            if parent:GetAlpha() < 0.1 then parent:SetAlpha(1) end
        end
    else
        -- 诊断：如果 debug 开启且长时间未触发，打印原因
        if HekiliHelper.DebugEnabled and (GetTime() - self.LastDiagnosticTime > 5) then
            HekiliHelper:DebugPrint(string.format("|cFF999999[DK] 运行中但未触发:|r %s", diagnostics or "检查中"))
            self.LastDiagnosticTime = GetTime()
        end

        if self.IsActive then
            if self.OverlayFrame then self.OverlayFrame:Hide() end
            HekiliHelper:DebugPrint(string.format("|cFFFF0000[DK] 停止渲染传染:|r (触发原因: %s)", self.LastReason or "判定失效"))
            self.IsActive = false
            self.LastReason = nil
        end
    end
end

function Module:ShouldRecommendPestilence()
    if not IsSpellKnown(PESTILENCE_SPELL_ID) then return false, nil, "技能未学习" end
    
    local runeReady = self:IsBloodOrDeathRuneReady()
    if not runeReady then return false, nil, "符文未就绪" end

    -- 1. 距离检查
    local distText = "未知"
    local RC = LibStub("LibRangeCheck-2.0")
    if RC then
        local _, maxRange = RC:GetRange("target")
        distText = tostring(maxRange or "超出检测范围")
        if maxRange and maxRange > 3 then return false, nil, "目标过远 ("..distText.."码)" end
    end

    -- 2. 获取双病状态
    local hasFF, ffTime, hasBP, bpTime = self:GetTargetDiseaseStatus()
    local diseaseInfo = string.format("FF=%s(%.1f) BP=%s(%.1f)", tostring(hasFF), ffTime, tostring(hasBP), bpTime)

    -- 3. 核心判定: 扫描周围目标 (扩散和 TTD 判定)
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
                        local unitHealthPct = (UnitHealthMax(unit) > 0) and (UnitHealth(unit) / UnitHealthMax(unit) * 100) or 0
                        local ttd = self:GetTTD(unit) or (unitHealthPct > 95 and 99 or 0)
                        if ttd > 4.5 then anyOtherHighTTD = true end
                        if not self:UnitHasMyDiseases(unit) then noDiseaseCount = noDiseaseCount + 1 end
                    end
                end
            end
        end
    end

    -- 4. 判定逻辑
    if hasFF and hasBP then
        -- 情况 A: 扩散逻辑 (身边有目标没病)
        if noDiseaseCount >= 1 then
            return true, string.format("扩散-发现目标: 无病数=%d", noDiseaseCount)
        end

        -- 情况 B: 刷新逻辑 (考虑当前目标 TTD)
        local targetHealthPct = (UnitHealthMax("target") > 0) and (UnitHealth("target") / UnitHealthMax("target") * 100) or 0
        local targetTTD = self:GetTTD("target") or (targetHealthPct > 95 and 99 or 0)

        local isBoss = (UnitLevel("target") == -1 or UnitClassification("target") == "worldboss")
        
        -- 判定大军是否可用 (只有在 Boss 战且大军可用时，才需要提前刷新疾病以防爆发期断病)
        local armyReady = false
        if IsSpellKnown(ARMY_OF_THE_DEAD_ID) then
            local start, duration = GetSpellCooldown(ARMY_OF_THE_DEAD_ID)
            armyReady = (start == 0 or (GetTime() - start) >= duration)
        end
        
        local refreshThreshold = (isBoss and armyReady) and 5.5 or 3.0
        
        if ffTime < refreshThreshold or bpTime < refreshThreshold then
            -- 核心逻辑：当前目标 TTD >= 4.5 或身边有其他高 TTD 目标时才刷新
            if targetTTD >= 4.5 or anyOtherHighTTD then
                local ttdInfo = string.format("targetTTD=%.1f otherHigh=%s", targetTTD, tostring(anyOtherHighTTD))
                return true, string.format("刷新-时间不足: FF=%.1f BP=%.1f (%s)", ffTime, bpTime, ttdInfo)
            end
            -- 如果都不满足，则即使时间不足也不推荐刷新
            return false, nil, string.format("刷新-放弃(TTD过短): targetTTD=%.1f", targetTTD)
        end
    end

    return false, nil, "条件未满足 ("..diseaseInfo..")"
end

-- 兼容性占位
function Module:ForceInsertPestilence() end
function Module:InsertDeathKnightSkills() end
