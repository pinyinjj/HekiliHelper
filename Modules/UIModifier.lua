-- Modules/UIModifier.lua
-- UI 修改模组：用于精简 Hekili 界面
-- 隐藏冷却转盘、冷却数字等，只保留纯净的图标

local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.UIModifier then
            HH.UIModifier = {}
        end
    end)
    return
end

-- 创建模块对象
if not HekiliHelper.UIModifier then
    HekiliHelper.UIModifier = {}
end

local Module = HekiliHelper.UIModifier

-- 模块初始化
function Module:Initialize()
    if not Hekili then return false end
    
    HekiliHelper:DebugPrint("|cFF00FF00[UIModifier]|r 开始初始化 UI 精简逻辑...")
    
    -- Hook Hekili.Update，在每次更新后确保 UI 依然是精简的
    HekiliHelper.HookUtils.Hook(Hekili, "Update", function()
        -- 稍微延迟一点，确保 Hekili 已经更新完它的按钮状态
        C_Timer.After(0.01, function()
            Module:CleanUI()
        end)
    end, "after")
    
    return true
end

-- 清理 UI
function Module:CleanUI()
    if not Hekili or not Hekili.DisplayPool then return end
    
    -- 检查插件主开关
    if not HekiliHelper.DB.profile.enabled then return end

    for dispName, UI in pairs(Hekili.DisplayPool) do
        -- 我们主要处理 Primary 和 AOE 这种战斗相关的显示
        if UI and UI.Buttons then
            for i, button in ipairs(UI.Buttons) do
                -- 1. 隐藏冷却转盘 (Cooldown Swipe)
                if button.cooldown then
                    button.cooldown:SetAlpha(0)
                    button.cooldown:Hide()
                    
                    -- 更加彻底地关闭转圈效果
                    if button.cooldown.SetDrawSwipe then button.cooldown:SetDrawSwipe(false) end
                    if button.cooldown.SetDrawEdge then button.cooldown:SetDrawEdge(false) end
                    if button.cooldown.SetSwipeColor then button.cooldown:SetSwipeColor(0, 0, 0, 0) end
                    
                    -- 防止 Hekili 再次显示它
                    if not button.cooldown.HH_Hooked then
                        hooksecurefunc(button.cooldown, "Show", function(self) 
                            if HekiliHelper.DB.profile.enabled then
                                self:Hide() 
                                self:SetAlpha(0)
                                if self.SetDrawSwipe then self:SetDrawSwipe(false) end
                            end
                        end)
                        button.cooldown.HH_Hooked = true
                    end
                end

                -- 1.1 专门处理 GCD (有些 Hekili 版本可能有独立的 gcd 框架)
                if button.gcd then
                    button.gcd:SetAlpha(0)
                    button.gcd:Hide()
                    if button.gcd.SetDrawSwipe then button.gcd:SetDrawSwipe(false) end
                    if button.gcd.SetDrawEdge then button.gcd:SetDrawEdge(false) end
                    
                    if not button.gcd.HH_Hooked then
                        hooksecurefunc(button.gcd, "Show", function(self)
                            if HekiliHelper.DB.profile.enabled then
                                self:Hide()
                                self:SetAlpha(0)
                                if self.SetDrawSwipe then self:SetDrawSwipe(false) end
                            end
                        end)
                        button.gcd.HH_Hooked = true
                    end
                end

                -- 1.2 有些版本大写 GCD
                if button.GCD then
                    button.GCD:SetAlpha(0)
                    button.GCD:Hide()
                    if button.GCD.SetDrawSwipe then button.GCD:SetDrawSwipe(false) end
                    if not button.GCD.HH_Hooked then
                        hooksecurefunc(button.GCD, "Show", function(self)
                            if HekiliHelper.DB.profile.enabled then
                                self:Hide()
                                self:SetAlpha(0)
                                if self.SetDrawSwipe then self:SetDrawSwipe(false) end
                            end
                        end)
                        button.GCD.HH_Hooked = true
                    end
                end

                -- 1.3 遍历所有子框架，彻底清理任何 Cooldown 类型的对象
                local children = { button:GetChildren() }
                for _, child in ipairs(children) do
                    if child:IsObjectType("Cooldown") then
                        child:SetAlpha(0)
                        child:Hide()
                        if child.SetDrawSwipe then child:SetDrawSwipe(false) end
                        if not child.HH_Hooked then
                            hooksecurefunc(child, "Show", function(self)
                                if HekiliHelper.DB.profile.enabled then
                                    self:Hide()
                                    self:SetAlpha(0)
                                    if self.SetDrawSwipe then self:SetDrawSwipe(false) end
                                end
                            end)
                            child.HH_Hooked = true
                        end
                    end
                end
                
                -- 2. 隐藏冷却时间文字 (Cooldown Text)
                -- Hekili 通常使用 button.cd 或类似命名的 FontString
                if button.cd then
                    button.cd:SetAlpha(0)
                    button.cd:Hide()
                    
                    if not button.cd.HH_Hooked then
                        hooksecurefunc(button.cd, "Show", function(self) 
                            if HekiliHelper.DB.profile.enabled then
                                self:Hide()
                                self:SetAlpha(0)
                            end
                        end)
                        button.cd.HH_Hooked = true
                    end
                end
                
                -- 3. 有些 Hekili 版本使用系统自带的冷却文字，也需要拦截
                local cdName = button.GetName and button:GetName()
                if cdName then
                    local cd = _G[cdName.."Cooldown"]
                    if cd then
                        cd:SetAlpha(0)
                        cd:Hide()
                        if cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
                        if not cd.HH_Hooked then
                            hooksecurefunc(cd, "Show", function(self)
                                if HekiliHelper.DB.profile.enabled then
                                    self:Hide()
                                    self:SetAlpha(0)
                                    if self.SetDrawSwipe then self:SetDrawSwipe(false) end
                                end
                            end)
                            cd.HH_Hooked = true
                        end
                    end
                end
            end
        end
    end
end
