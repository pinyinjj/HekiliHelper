-- HekiliHelper.lua
-- 独立的Hekili辅助插件

local addonName = "HekiliHelper"
local HekiliHelper = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")

-- 确保对象在全局命名空间中可用（供模块文件访问）
_G.HekiliHelper = HekiliHelper

HekiliHelper.Version = "1.0.0"

-- 检查Hekili是否已加载
local function CheckHekiliLoaded()
    if not Hekili then
        return false
    end
    
    -- 等待Hekili完全初始化
    if not Hekili.Update then
        return false
    end
    
    return true
end

function HekiliHelper:OnInitialize()
    self:Print("|cFF00FF00[HekiliHelper]|r 插件已加载，版本 " .. self.Version)
    
    -- 创建模块对象（如果模块文件已加载）
    if not self.MeleeTargetIndicator then
        self.MeleeTargetIndicator = {}
        self:Print("|cFF00FF00[HekiliHelper]|r 创建MeleeTargetIndicator模块对象")
    else
        self:Print("|cFF00FF00[HekiliHelper]|r MeleeTargetIndicator模块对象已存在")
    end
end

function HekiliHelper:OnEnable()
    self:Print("|cFF00FF00[HekiliHelper]|r 插件已启用，等待Hekili加载...")
    
    -- 使用定时器检查Hekili是否已加载（因为ADDON_LOADED事件可能已经触发）
    local checkCount = 0
    local maxChecks = 20  -- 最多检查20次（10秒）
    
    local function CheckAndInit()
        checkCount = checkCount + 1
        
        if CheckHekiliLoaded() then
            self:Print("|cFF00FF00[HekiliHelper]|r 检测到Hekili已加载，初始化模块...")
            self:InitializeModules()
        elseif checkCount < maxChecks then
            -- 继续等待
            C_Timer.After(0.5, CheckAndInit)
        else
            self:Print("|cFFFF0000[HekiliHelper]|r 超时: 无法检测到Hekili加载")
        end
    end
    
    -- 立即检查一次
    C_Timer.After(0.5, CheckAndInit)
end


function HekiliHelper:OnDisable()
    -- 插件禁用时的逻辑
end

-- 初始化所有模块
function HekiliHelper:InitializeModules()
    if not CheckHekiliLoaded() then
        self:Print("|cFFFF0000[HekiliHelper]|r 错误: Hekili未加载，无法初始化模块")
        -- 再次尝试延迟初始化
        C_Timer.After(2.0, function()
            if CheckHekiliLoaded() then
                self:InitializeModules()
            else
                self:Print("|cFFFF0000[HekiliHelper]|r 错误: 延迟初始化失败，Hekili仍未加载")
            end
        end)
        return
    end
    
    self:Print("|cFF00FF00[HekiliHelper]|r 正在初始化模块...")
    self:Print("|cFF00FF00[HekiliHelper]|r Hekili.Update存在: " .. (Hekili.Update and "是" or "否"))
    
    -- 检查模块是否存在
    if not self.MeleeTargetIndicator then
        self:Print("|cFFFF0000[HekiliHelper]|r 错误: MeleeTargetIndicator模块未找到")
        return
    end
    
    self:Print("|cFF00FF00[HekiliHelper]|r 找到MeleeTargetIndicator模块，开始初始化...")
    
    -- 加载模块
    local success = self.MeleeTargetIndicator:Initialize()
    if success then
        self:Print("|cFF00FF00[HekiliHelper]|r 模块初始化成功")
    else
        self:Print("|cFFFF0000[HekiliHelper]|r 模块初始化失败")
    end
end

-- Hook工具函数（类似PatchUtils）
HekiliHelper.HookUtils = {
    -- Hook函数（在函数执行前后添加逻辑）
    Hook = function(target, funcName, hookFunc, position)
        position = position or "after"  -- "before" 或 "after"
        
        if not target[funcName] then
            HekiliHelper:Print("|cFFFF0000[HekiliHelper]|r 错误: 函数 " .. funcName .. " 不存在")
            return false
        end
        
        local originalFunc = target[funcName]
        
        if position == "after" then
            target[funcName] = function(...)
                local result = originalFunc(...)
                hookFunc(originalFunc, ...)
                return result
            end
        else
            target[funcName] = function(...)
                hookFunc(originalFunc, ...)
                return originalFunc(...)
            end
        end
        
        return true
    end,
    
    -- 包装函数（完全控制函数执行）
    Wrap = function(target, funcName, wrapperFunc)
        if not target[funcName] then
            HekiliHelper:Print("|cFFFF0000[HekiliHelper]|r 错误: 函数 " .. funcName .. " 不存在")
            return false
        end
        
        local originalFunc = target[funcName]
        target[funcName] = function(self, ...)
            return wrapperFunc(originalFunc, self, ...)
        end
        
        return true
    end
}

