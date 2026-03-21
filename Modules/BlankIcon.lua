-- Modules/BlankIcon.lua
-- 空白图标模组
-- 当没有任何推荐技能时，在Hekili界面插入一个纯白色的空白图标

local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.BlankIcon then
            HH.BlankIcon = {}
        end
    end)
    return
end

-- 创建模块对象
if not HekiliHelper.BlankIcon then
    HekiliHelper.BlankIcon = {}
end

local Module = HekiliHelper.BlankIcon

-- 拦截 SetAlpha 的函数
local function HookSetAlpha(frame)
    if frame.HekiliHelperHooked then return end
    
    local originalSetAlpha = frame.SetAlpha
    frame.SetAlpha = function(self, alpha)
        -- 如果这个窗体当前包含我们的空白图标，且有人想把它设为不可见 (alpha < 0.1)
        -- 则强制保持可见
        if self.Recommendations and self.Recommendations[1] and self.Recommendations[1].isBlankIcon and alpha < 0.1 then
            return originalSetAlpha(self, 1.0)
        end
        return originalSetAlpha(self, alpha)
    end
    
    frame.HekiliHelperHooked = true
end

-- 模块初始化
function Module:Initialize()
    if not Hekili then
        return false
    end
    
    -- Hook Hekili.Update函数
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        
        -- 在 Hekili 计算完后立即介入
        C_Timer.After(0.001, function()
            Module:InsertBlankIcon()
        end)
        
        return result
    end)
    
    return success
end

-- 插入空白图标
function Module:InsertBlankIcon()
    if not Hekili or not Hekili.DisplayPool then return end
    
    local displays = Hekili.DisplayPool
    
    for dispName, UI in pairs(displays) do
        local lowerName = dispName:lower()
        -- 只处理 Primary 和 AOE 显示
        if (lowerName == "primary" or lowerName == "aoe") and UI then
            -- 1. 确保 Hook 了 SetAlpha
            HookSetAlpha(UI)
            
            -- 2. 处理显示逻辑
            self:ProcessDisplay(dispName, UI)
        end
    end
end

-- 处理单个显示
function Module:ProcessDisplay(dispName, UI)
    if not UI.Recommendations then return end
    
    local Queue = UI.Recommendations
    local hasRecommendation = false
    local blankIconsFound = {}
    
    -- 1. 扫描整个队列（检查前10个槽位，确保覆盖全面）
    for i = 1, 10 do
        if Queue[i] then
            if Queue[i].isBlankIcon then
                table.insert(blankIconsFound, i)
            elseif Queue[i].actionName and Queue[i].actionName ~= "" and Queue[i].actionName ~= "blank_icon" then
                hasRecommendation = true
            end
        end
    end
    
    -- 2. 逻辑处理
    if hasRecommendation then
        -- 如果有真实推荐，移除所有发现的空白图标
        if #blankIconsFound > 0 then
            for _, index in ipairs(blankIconsFound) do
                Queue[index] = nil
            end
            UI.NewRecommendations = true
        end
    else
        -- 没有任何真实推荐
        -- 如果队列中还没有空白图标，则在位置1插入一个
        if #blankIconsFound == 0 then
            -- 确保位置1被占用
            Queue[1] = Queue[1] or {}
            local slot = Queue[1]
            
            local whiteTexture = "Interface\\Buttons\\WHITE8X8"
            
            slot.index = 1
            slot.actionName = "blank_icon"
            slot.actionID = 0
            slot.texture = whiteTexture
            slot.time = 0
            slot.exact_time = GetTime()
            slot.delay = 0
            slot.since = 0
            slot.resources = {}
            slot.depth = 0
            slot.display = dispName
            slot.isBlankIcon = true
            
            if not Hekili.Class.abilities["blank_icon"] then
                Hekili.Class.abilities["blank_icon"] = {
                    key = "blank_icon",
                    name = "空白占位",
                    texture = whiteTexture,
                    id = 0,
                    cast = 0,
                    gcd = "off",
                }
            end
            
            -- 强制 UI 刷新状态
            UI.Active = true
            UI.alpha = 1.0
            UI:SetAlpha(1.0) -- 这会触发我们的 Hook
            UI.NewRecommendations = true
        end
    end
end
