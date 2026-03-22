-- Modules/FeralDruidSkills.lua
-- 野性德鲁伊技能模块
-- 采用“UI覆盖逻辑”：在 Hekili 推荐精灵火时叠加愈合图标，不修改原生队列，彻底解决闪烁。
-- 触发条件：玩家拥有“掠食者的迅捷”Buff 且 Hekili 当前推荐精灵之火。

local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.FeralDruidSkills then
            HH.FeralDruidSkills = {}
        end
    end)
    return
end

if not HekiliHelper.FeralDruidSkills then
    HekiliHelper.FeralDruidSkills = {}
end

local Module = HekiliHelper.FeralDruidSkills

-- 技能ID定义
local REGROWTH_SPELL_ID = 48443 
local FAERIE_FIRE_FERAL_ID = 16857 
local FAERIE_FIRE_ID = 770 
local PREDATORY_SWIFTNESS_ID = 69369

-- 状态变量
Module.IsActive = false
Module.OverlayFrames = {} -- 存储不同窗口的覆盖层
Module.LastReason = nil
Module.LastDiagnosticTime = 0

-- ===== 辅助判定函数 =====

function Module:HasPredatorySwiftness()
    for i = 1, 40 do
        local name, _, _, _, _, _, unitCaster, _, _, spellId = UnitBuff("player", i)
        if not name then break end
        if spellId == PREDATORY_SWIFTNESS_ID and unitCaster == "player" then
            return true
        end
    end
    return false
end

-- ===== UI 覆盖层实现 =====

function Module:GetOverlayFrame(dispName, parent)
    if self.OverlayFrames[dispName] then return self.OverlayFrames[dispName] end
    if not parent then return nil end

    local size = 50
    if Hekili and Hekili.DB and Hekili.DB.profile and Hekili.DB.profile.displays then
        local cfg = Hekili.DB.profile.displays[dispName] or Hekili.DB.profile.displays.Primary
        size = cfg.primaryIconSize or cfg.buttonSize or 50
    end

    local f = CreateFrame("Frame", "HekiliHelperFeralOverlay_"..dispName, parent)
    f:SetSize(size, size)
    f:SetPoint("CENTER", parent, "CENTER")
    f:SetFrameLevel(parent:GetFrameLevel() + 100)
    
    f.texture = f:CreateTexture(nil, "OVERLAY")
    f.texture:SetAllPoints(f)
    f.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(REGROWTH_SPELL_ID) or select(3, GetSpellInfo(REGROWTH_SPELL_ID))
    f.texture:SetTexture(icon)

    -- 发光效果 (粉色)
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.glow:SetColorTexture(1, 0.4, 0.7, 0.5)

    f:Hide()
    self.OverlayFrames[dispName] = f
    return f
end

function Module:Initialize()
    HekiliHelper:DebugPrint("[Feral] ===== Initialize (Overlay模式) 开始 =====")
    
    if not Hekili or not Hekili.Update then
        C_Timer.After(1.0, function() Module:Initialize() end)
        return false
    end

    local _, class = UnitClass("player")
    if class ~= "DRUID" then return true end

    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        Module:ProcessFeralOverlay()
        return result
    end)

    if success then
        HekiliHelper:DebugPrint("[Feral] ===== Hook成功，覆盖模式已激活 =====")
    end
    return success
end

function Module:ProcessFeralOverlay()
    -- 检查模块开关
    local db = HekiliHelper.DB and HekiliHelper.DB.profile and HekiliHelper.DB.profile.feralDruid
    if not db or db.enabled == false then
        self:HideAllOverlays()
        return
    end

    local shouldShow, reason, diagnostics = self:CheckConditions()
    
    if shouldShow then
        local foundParent = false
        -- 遍历 Hekili 显示池，在 Primary 和 AOE 的第一个按钮上渲染
        for dispName, UI in pairs(Hekili.DisplayPool) do
            local lowerName = dispName:lower()
            if (lowerName == "primary" or lowerName == "aoe") and UI.Active and UI.Buttons and UI.Buttons[1] then
                local parent = UI.Buttons[1]
                local overlay = self:GetOverlayFrame(dispName, parent)
                if overlay then
                    overlay:Show()
                    if not parent:IsShown() then parent:Show() end
                    if parent:GetAlpha() < 0.1 then parent:SetAlpha(1) end
                    foundParent = true
                end
            end
        end

        if foundParent then
            if not self.IsActive then
                self.LastReason = reason
                HekiliHelper:DebugPrint(string.format("|cFFFF66CC[Feral] 开始渲染愈合:|r %s", reason or "满足触发条件"))
                self.IsActive = true
            end
        end
    else
        -- 诊断日志
        if HekiliHelper.DebugEnabled and (GetTime() - self.LastDiagnosticTime > 5) then
            HekiliHelper:DebugPrint(string.format("|cFF999999[Feral] 运行中未触发:|r %s", diagnostics or "检查中"))
            self.LastDiagnosticTime = GetTime()
        end
        self:HideAllOverlays()
    end
end

function Module:HideAllOverlays()
    if self.IsActive then
        for _, overlay in pairs(self.OverlayFrames) do
            overlay:Hide()
        end
        HekiliHelper:DebugPrint(string.format("|cFFFF3366[Feral] 停止渲染愈合:|r (触发原因: %s)", self.LastReason or "判定失效"))
        self.IsActive = false
        self.LastReason = nil
    end
end

function Module:CheckConditions()
    -- 1. 基础条件
    if not self:HasPredatorySwiftness() then return false, nil, "缺失掠食者的迅捷Buff" end
    if UnitPower("player", 0) <= 2500 then return false, nil, "法力值过低" end

    -- 2. 检查 Hekili 原生推荐是否为精灵火
    local ffRecommended = false
    local currentRec = "无"
    
    for dispName, UI in pairs(Hekili.DisplayPool) do
        local lowerName = dispName:lower()
        if (lowerName == "primary" or lowerName == "aoe") and UI.Active then
            local Queue = UI.Recommendations
            if Queue and Queue[1] then
                local action = Queue[1].actionName or ""
                local id = Queue[1].actionID or 0
                currentRec = action
                if action == "faerie_fire_feral" or action == "faerie_fire" or id == FAERIE_FIRE_FERAL_ID or id == FAERIE_FIRE_ID then
                    ffRecommended = true
                    break
                end
            end
        end
    end

    if ffRecommended then
        return true, "检测到推荐精灵火且拥有迅捷Buff", nil
    end

    return false, nil, "当前推荐非精灵火 ("..currentRec..")"
end

-- 兼容性占位
function Module:InsertRegrowth() end
function Module:RemoveRegrowth() end
