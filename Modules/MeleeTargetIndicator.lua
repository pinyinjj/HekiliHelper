-- Modules/MeleeTargetIndicator.lua
-- 近战目标指示器模块
-- 采用“UI覆盖逻辑”：在 Hekili 主图标上叠加职业图标，不修改原生队列，彻底解决闪烁。
-- 触发条件：玩家身边5码内有敌人，但玩家没有目标或未处于近战攻击状态。

local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.MeleeTargetIndicator then
            HH.MeleeTargetIndicator = {}
        end
    end)
    return
end

if not HekiliHelper.MeleeTargetIndicator then
    HekiliHelper.MeleeTargetIndicator = {}
end

local Module = HekiliHelper.MeleeTargetIndicator

-- 状态变量
Module.IsActive = false
Module.OverlayFrame = nil
Module.LastReason = nil
Module.LastDiagnosticTime = 0

-- ===== 辅助判定函数 =====

function Module:GetClassIconPath()
    local _, class = UnitClass("player")
    if not class then return nil end
    local classIcons = {
        DEATHKNIGHT = "Interface\\AddOns\\Hekili\\Textures\\DEATHKNIGHT.blp",
        DRUID = "Interface\\AddOns\\Hekili\\Textures\\DRUID.blp",
        HUNTER = "Interface\\AddOns\\Hekili\\Textures\\HUNTER.png",
        MAGE = "Interface\\AddOns\\Hekili\\Textures\\MAGE.blp",
        PALADIN = "Interface\\AddOns\\Hekili\\Textures\\PALADIN.blp",
        PRIEST = "Interface\\AddOns\\Hekili\\Textures\\PRIEST.blp",
        ROGUE = "Interface\\AddOns\\Hekili\\Textures\\ROGUE.blp",
        SHAMAN = "Interface\\AddOns\\Hekili\\Textures\\SHAMAN.blp",
        WARLOCK = "Interface\\AddOns\\Hekili\\Textures\\WARLOCK.blp",
        WARRIOR = "Interface\\AddOns\\Hekili\\Textures\\WARRIOR.blp",
    }
    return classIcons[class]
end

function Module:IsInMeleeCombat()
    if IsCurrentSpell(6603) then return true end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return true end
    if Hekili.State and Hekili.State.buff and Hekili.State.buff.casting and Hekili.State.buff.casting.up then
        return true
    end
    return false
end

function Module:CountEnemiesInMeleeRange()
    local RC = LibStub("LibRangeCheck-2.0")
    if not RC then return 0 end
    local count = 0
    local checked = {}
    
    local units = {"target", "focus", "mouseover"}
    for i = 1, 40 do table.insert(units, "nameplate"..i) end
    
    for _, unit in ipairs(units) do
        if UnitExists(unit) and not UnitIsDead(unit) and UnitCanAttack("player", unit) then
            local guid = UnitGUID(unit)
            if guid and not checked[guid] then
                checked[guid] = true
                local _, maxRange = RC:GetRange(unit)
                if (not maxRange) or (maxRange <= 5) then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- ===== UI 覆盖层实现 =====

function Module:GetHekiliPrimaryButton()
    if not Hekili or not Hekili.DisplayPool then return nil end
    local displays = Hekili.DisplayPool
    local UI = displays.Primary or displays.primary
    if UI and UI.Buttons and UI.Buttons[1] then return UI.Buttons[1] end
    for _, disp in pairs(displays) do
        if type(disp) == "table" and disp.Buttons and disp.Buttons[1] then return disp.Buttons[1] end
    end
    return _G["HekiliDisplayPrimary"] and _G["HekiliDisplayPrimary"].Buttons and _G["HekiliDisplayPrimary"].Buttons[1]
end

function Module:CreateOverlay()
    if self.OverlayFrame then return self.OverlayFrame end
    local parent = self:GetHekiliPrimaryButton()
    if not parent then return nil end

    local size = 50
    if Hekili and Hekili.DB and Hekili.DB.profile and Hekili.DB.profile.displays then
        for _, cfg in pairs(Hekili.DB.profile.displays) do
            if cfg.primaryIconSize or cfg.buttonSize then
                size = cfg.primaryIconSize or cfg.buttonSize
                break
            end
        end
    end

    local f = CreateFrame("Frame", "HekiliHelperMeleeOverlay", parent)
    f:SetSize(size, size)
    f:SetPoint("CENTER", parent, "CENTER")
    f:SetFrameStrata("TOOLTIP") -- 显式设为最高层级
    f:SetFrameLevel(9000)      -- 使用极高的绝对层级压过数字
    
    f.texture = f:CreateTexture(nil, "OVERLAY")
    f.texture:SetAllPoints(f)
    f.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    f.texture:SetTexture(self:GetClassIconPath())

    -- 发光效果 (蓝色区分于传染的绿色)
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.glow:SetColorTexture(0, 0.6, 1, 0.5)

    f:Hide()
    self.OverlayFrame = f
    return f
end

function Module:Initialize()
    HekiliHelper:DebugPrint("[Melee] ===== Initialize (Overlay模式) 开始 =====")
    
    if not Hekili or not Hekili.Update then
        C_Timer.After(1.0, function() Module:Initialize() end)
        return false
    end

    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        Module:ProcessMeleeOverlay()
        return result
    end)

    if success then
        HekiliHelper:DebugPrint("[Melee] ===== Hook成功，覆盖模式已激活 =====")
    end
    return success
end

function Module:ProcessMeleeOverlay()
    -- 检查模块开关
    local db = HekiliHelper.DB and HekiliHelper.DB.profile and HekiliHelper.DB.profile.meleeIndicator
    if not db or not db.enabled then
        if self.IsActive then
            if self.OverlayFrame then self.OverlayFrame:Hide() end
            self.IsActive = false
        end
        return
    end

    local shouldShow, reason, diagnostics = self:ShouldShowIndicator()
    local overlay = self:CreateOverlay()
    
    if shouldShow then
        if not overlay then return end

        if not self.IsActive then
            self.LastReason = reason
            HekiliHelper:DebugPrint(string.format("|cFF00CCFF[Melee] 开始渲染指示:|r %s", reason or "未知"))
            self.IsActive = true
        end
        
        overlay:Show()
        local parent = overlay:GetParent()
        if parent then
            if not parent:IsShown() then parent:Show() end
            if parent:GetAlpha() < 0.1 then parent:SetAlpha(1) end
        end
    else
        -- 诊断日志
        if HekiliHelper.DebugEnabled and (GetTime() - self.LastDiagnosticTime > 5) then
            HekiliHelper:DebugPrint(string.format("|cFF999999[Melee] 运行中未触发:|r %s", diagnostics or "检查中"))
            self.LastDiagnosticTime = GetTime()
        end

        if self.IsActive then
            if self.OverlayFrame then self.OverlayFrame:Hide() end
            HekiliHelper:DebugPrint(string.format("|cFFCC3333[Melee] 停止渲染指示:|r (触发原因: %s)", self.LastReason or "判定失效"))
            self.IsActive = false
            self.LastReason = nil
        end
    end
end

function Module:ShouldShowIndicator()
    local enemies = self:CountEnemiesInMeleeRange()
    local inMelee = self:IsInMeleeCombat()
    
    local diag = string.format("5码敌人=%d 正在近战=%s", enemies, tostring(inMelee))

    if enemies > 0 and not inMelee then
        return true, string.format("发现%d个近战敌人且未处于战斗状态", enemies)
    end

    return false, nil, diag
end

-- 兼容性占位
function Module:ForceInsertMeleeIndicator() end
function Module:InsertMeleeIndicator() end
function Module:RemoveMeleeIndicator() end
