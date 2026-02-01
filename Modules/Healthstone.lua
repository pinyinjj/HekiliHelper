-- Modules/Healthstone.lua
-- 灵魂石（治疗石）推荐模块
-- 当生命值低且背包中有治疗石时，提示使用

local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.Healthstone then
            HH.Healthstone = {}
        end
    end)
    return
end

if not HekiliHelper.Healthstone then
    HekiliHelper.Healthstone = {}
end

local Module = HekiliHelper.Healthstone

function Module:Initialize()
    if not Hekili then return false end
    if not Hekili.Update then return false end
    
    HekiliHelper:DebugPrint("|cFF00FF00[Healthstone]|r 模块初始化...")
    
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local savedSkills = {}
        if Hekili and Hekili.DisplayPool then
            for dispName, UI in pairs(Hekili.DisplayPool) do
                if UI and UI.Recommendations then
                    local Queue = UI.Recommendations
                    savedSkills[dispName] = {}
                    for i = 1, 4 do
                        if Queue[i] and Queue[i].isHealthstone then
                            savedSkills[dispName][i] = {}
                            for k, v in pairs(Queue[i]) do
                                savedSkills[dispName][i][k] = v
                            end
                        end
                    end
                end
            end
        end
        
        local result = oldFunc(self, ...)
        
        C_Timer.After(0.001, function()
            -- 恢复被清除的技能
            if Hekili and Hekili.DisplayPool then
                for dispName, saved in pairs(savedSkills) do
                    local UI = Hekili.DisplayPool[dispName]
                    if UI and UI.Recommendations then
                        local Queue = UI.Recommendations
                        for i, savedSlot in pairs(saved) do
                            if not Queue[i] or not Queue[i].isHealthstone then
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
            
            -- 插入新推荐
            Module:InsertHealthstone()
        end)
        
        return result
    end)
    
    return success
end

-- 检查是否应该使用灵魂石
function Module:CheckHealthstone()
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db then return false end
    
    -- 默认启用，但在UI中配置
    if db.healthstone and db.healthstone.enabled == false then
        return false
    end
    
    local itemID = 36892 -- 邪能治疗石
    
    -- 1. 检查背包中是否有该物品
    if GetItemCount(itemID) == 0 then
        return false
    end
    
    -- 2. 检查冷却
    local start, duration, enable = GetItemCooldown(itemID)
    if start and duration and (start > 0 and duration > 1.5) then -- 忽略GCD
        local remaining = (start + duration) - GetTime()
        if remaining > 0 then
            return false
        end
    end
    
    -- 3. 检查生命值
    local threshold = (db.healthstone and db.healthstone.threshold) or 70
    local healthPercent = (UnitHealth("player") / UnitHealthMax("player")) * 100
    
    if healthPercent >= threshold then
        return false
    end
    
    return true
end

function Module:InsertHealthstone()
    if not Hekili then return end
    
    -- 检查是否需要插入
    if not self:CheckHealthstone() then
        -- 如果不需要插入，移除已存在的（如果有）
        self:RemoveHealthstone()
        return
    end
    
    local displays = Hekili.DisplayPool
    if not displays then return end
    
    for dispName, UI in pairs(displays) do
        if (dispName == "Primary" or dispName == "AOE") and UI.Active and UI.alpha > 0 then
            self:InsertItemForDisplay(dispName, UI)
        end
    end
end

function Module:RemoveHealthstone()
    local displays = Hekili.DisplayPool
    if not displays then return end
    
    for dispName, UI in pairs(displays) do
        if UI.Recommendations then
            local Queue = UI.Recommendations
            for i = 1, 4 do
                if Queue[i] and Queue[i].isHealthstone then
                    -- 移除
                    if Queue[i].originalRecommendation then
                        local original = Queue[i].originalRecommendation
                        for k, v in pairs(Queue[i]) do Queue[i][k] = nil end
                        for k, v in pairs(original) do Queue[i][k] = v end
                    else
                        Queue[i] = {}
                    end
                    UI.NewRecommendations = true
                end
            end
        end
    end
end

function Module:InsertItemForDisplay(dispName, UI)
    if not UI or not UI.Recommendations then return end
    local Queue = UI.Recommendations
    
    local itemID = 36892
    local actionName = "healthstone_36892"
    
    -- 检查是否已经存在
    for i = 1, 4 do
        if Queue[i] and Queue[i].isHealthstone then
            -- 已经存在，更新一下纹理等（以防万一）
            return 
        end
    end
    
    -- 插入到位置1（最高优先级保命）
    local insertIndex = 1
    
    -- 保存原始推荐
    local originalSlot = nil
    if Queue[insertIndex] and Queue[insertIndex].actionName and not Queue[insertIndex].isHealthstone then
        originalSlot = {}
        for k, v in pairs(Queue[insertIndex]) do
            originalSlot[k] = v
        end
    end
    
    -- 获取物品信息
    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
    if not itemName then 
        -- 尝试请求物品信息
        return 
    end
    
    -- 准备Action
    Queue[insertIndex] = Queue[insertIndex] or {}
    local slot = Queue[insertIndex]
    
    slot.index = insertIndex
    slot.actionName = actionName
    slot.actionID = itemID
    slot.texture = itemTexture
    slot.time = 0
    slot.exact_time = GetTime()
    slot.isHealthstone = true
    slot.originalRecommendation = originalSlot
    
    -- 注册虚拟Ability以便显示
    if Hekili.Class and Hekili.Class.abilities then
        if not Hekili.Class.abilities[actionName] then
            Hekili.Class.abilities[actionName] = {
                key = actionName,
                name = itemName,
                texture = itemTexture,
                id = itemID,
                cast = 0,
                gcd = "off",
                item = true 
            }
        end
        slot.action = Hekili.Class.abilities[actionName]
    end
    
    UI.NewRecommendations = true
    HekiliHelper:DebugPrint("|cFF00FF00[Healthstone]|r 插入治疗石推荐")
end
